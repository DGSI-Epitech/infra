# Architecture

Infrastructure as Code pour un lab école déployé sur deux sites Proxmox.
Objectif : lab entièrement reproductible en moins de 10 minutes sur un environnement vierge.

---

## Vue d'ensemble

```
                        ┌─────────────────────────────────────────────────┐
                        │                  GitHub Actions                  │
                        │  push → terraform apply → ansible-playbook       │
                        └───────────────────┬─────────────────────────────┘
                                            │ self-hosted runner
                   ┌────────────────────────┴─────────────────────────┐
                   │                                                   │
          ┌────────▼────────┐                              ┌──────────▼──────────┐
          │   PVE1 (local)  │                              │   PVE2 (cloud)      │
          │  51.75.128.134  │                              │  ns3183326.ip-...   │
          │                 │                              │                     │
          │  pfSense S1     │  ◄── OpenVPN 10.3.3.0/29 ──►│  pfSense S2         │
          │  LAN: 172.16.0.0/24                            │  LAN: .240/28       │
          │                 │                              │  DMZ: .248/29       │
          │  services-vm    │                              │  Teleport (bastion) │
          │  vault-vm       │                              │  website            │
          └─────────────────┘                              └─────────────────────┘
```

---

## Flux de déploiement

```
Jour 0 — Bootstrap (une seule fois)
  terraform/envs/bootstrap/
    └─► Crée TerraformRole + token root@pam!terraform sur Proxmox

Jour 1+ — Déploiement standard via npm run deploy
  Packer
    └─► Build template pfSense (ID 2000) sur Proxmox

  Packer
    └─► Build template Ubuntu (ID 1000) sur Proxmox

  Terraform (terraform/envs/onprem/)
    ├─► Clone pfSense template → pfsense-fw-01 (ID 2100)
    ├─► Clone Ubuntu template  → services-vm (ID 1100) + cloud-init IP
    └─► Clone Ubuntu template  → vault-vm (ID 1200) + cloud-init IP

  Ansible (inventory/onprem.py — dynamique depuis config.env)
    ├─► roles/base  → Docker, UFW, paquets de base (toutes les VMs)
    └─► roles/vault → HashiCorp Vault install + init + unseal
```

---

## Composants

### terraform/envs/bootstrap/

Tourne **une seule fois** sur un Proxmox vierge. S'authentifie avec `root@pam` username/password, crée le rôle `TerraformRole` avec les privileges nécessaires, génère le token `root@pam!terraform` et lui assigne le rôle. Output : le token à injecter dans `TF_VAR_proxmox_api_token`.

### terraform/envs/onprem/

Environnement principal PVE1. Appelle quatre modules :

| Module | Ressource créée | ID Proxmox |
|---|---|---|
| `pfsense` | Clone le template pfSense Packer | 2100 |
| `services-vm` | Clone le template Ubuntu, IP `172.16.0.241/24` | 1100 |
| `vault-vm` | Clone le template Ubuntu, IP `172.16.0.242/24` | 1200 |

### packer/pfsense-2.7/

Build automatisé du template pfSense via séquence de touches clavier simulées. Injecte `config.xml.pkrtpl.hcl` (template Packer) via un CD virtuel — contient les interfaces vtnet, IP LAN `172.16.0.254/24`, DNS, SSH activé, et la clé SSH publique admin. Produit le template ID 2000 sur Proxmox.

### packer/ubuntu-22.04/

Build automatisé du template Ubuntu 22.04 via autoinstall. Utilise un password éphémère (généré dans deploy.sh, jamais stocké) pour le communicator SSH. Injecte la clé SSH via provisioner, désactive le password SSH, nettoie le template. Produit le template ID 1000 sur Proxmox.

### ansible/

| Playbook | Rôles | Cible |
|---|---|---|
| `playbooks/services-vm.yml` | `base` | services-vm |
| `playbooks/vault.yml` | `base`, `vault` | vault-vm |

L'inventaire `inventory/onprem.py` est un script Python dynamique qui lit `config.env`. Les IPs, la clé SSH et le ProxyJump SSH (via Proxmox) sont toujours cohérents avec l'environnement déployé.

Le rôle `vault` installe HashiCorp Vault, configure le stockage Raft, init + unseal automatique, sauvegarde les unseal keys dans `/root/vault-init.json` sur la vault-vm.

---

## Réseau

### PVE1 — On-premise

| Élément | Valeur |
|---|---|
| Proxmox IP publique | `51.75.128.134` |
| Proxmox node | `proxmox-site1` |
| WAN pfSense | `vmbr0` (IP publique) |
| LAN pfSense | `vmbr1` — `172.16.0.254/24` |
| Réseau LAN | `172.16.0.0/24` |

| VM | ID | IP | Rôle |
|---|---|---|---|
| ubuntu-template | 1000 | — | Template Ubuntu (ne pas démarrer) |
| pfsense-template | 2000 | — | Template pfSense (ne pas démarrer) |
| pfsense-fw-01 | 2100 | `172.16.0.254` | Pare-feu LAN/WAN |
| services-vm | 1100 | `172.16.0.241` | Netbox, website |
| vault-vm | 1200 | `172.16.0.242` | HashiCorp Vault |

### PVE2 — Cloud

| VM | IP | Réseau | Rôle |
|---|---|---|---|
| Teleport | `10.255.255.249` | DMZ `10.255.255.248/29` | Bastion SSH |
| website | `192.168.255.243` | LAN `192.168.255.240/28` | Site web |

### Tunnel inter-sites

OpenVPN sur `10.3.3.0/29` entre pfSense S1 (PVE1) et pfSense S2 (PVE2).

---

## CI/CD

```
push main
  ├── packer/**     → packer.yml    → packer build (templates)
  └── terraform/**
      ansible/**    → deploy-onprem.yml
                         ├── terraform init + plan + apply
                         ├── injection clé SSH via QEMU agent
                         ├── attente SSH (ProxyJump via Proxmox)
                         └── ansible-playbook -i inventory/onprem.py
```

Les deux workflows tournent sur un **self-hosted runner** installé sur le réseau Proxmox (accès direct aux IPs `172.16.0.x`).

---

## Décisions techniques

| Décision | Raison |
|---|---|
| Template Ubuntu via Packer | Contrôle total du build — password éphémère, clé SSH injectée par provisioner |
| Template pfSense via Packer | pfSense n'a pas de cloud-init — config injectée via CD (config.xml template) |
| Vault en mode Raft | Pas de dépendance externe (pas de Consul), single-node suffisant pour le lab |
| `bpg/proxmox` provider | Support cloud-init, download_file, SSH pour import disque |
| Bootstrap Terraform séparé | Évite la dépendance circulaire token/permissions — tourne une seule fois |
| Inventaire Ansible dynamique (Python) | IPs et ProxyJump toujours cohérents avec config.env, pas de duplication |
| QEMU agent pour injection clé SSH | cloud-init ne met pas à jour authorized_keys pour un user créé par autoinstall |
| ProxyJump Proxmox pour Ansible | VMs sur vmbr1 (réseau privé), inaccessibles directement depuis l'extérieur |
