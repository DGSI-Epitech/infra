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
          │  192.168.139.128│                              │  ns3183326.ip-...   │
          │                 │                              │                     │
          │  pfSense S1     │  ◄── OpenVPN 10.3.3.0/29 ──►│  pfSense S2         │
          │  LAN: .240/28   │                              │  LAN: .240/28       │
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

Jour 1+ — Déploiement standard
  Packer
    └─► Build template pfSense (ID 9001) sur Proxmox

  Terraform (terraform/envs/onprem/)
    ├─► Télécharge Ubuntu 22.04 cloud-image
    ├─► Crée template Ubuntu (ID 9001)
    ├─► Clone → services-vm (ID 200) + cloud-init IP/SSH
    ├─► Clone → vault-vm (ID 201) + cloud-init IP/SSH
    └─► Clone template pfSense → pfsense-fw-01

  Ansible (lancé automatiquement par deploy.sh Phase 5)
    ├─► roles/base     → Docker, UFW, paquets de base (toutes les VMs)
    └─► roles/vault    → HashiCorp Vault install + init + unseal automatique
```

---

## Composants

### terraform/envs/bootstrap/

Tourne **une seule fois** sur un Proxmox vierge. S'authentifie avec `root@pam` username/password, crée le rôle `TerraformRole` avec les privileges nécessaires, génère le token `root@pam!terraform` et lui assigne le rôle. Output : le token à injecter dans `TF_VAR_proxmox_api_token`.

### terraform/envs/onprem/

Environnement principal PVE1. Appelle quatre modules :

| Module | Ressource créée | ID Proxmox |
|---|---|---|
| `ubuntu-template` | Build Packer + crée la template Ubuntu | 9000 |
| `pfsense` | Clone la template pfSense Packer | 1001 |
| `services-vm` | Clone la template, IP `172.16.0.241/24` | 1100 |
| `vault-vm` | Clone la template, IP `172.16.0.242/24` | 1200 |

### packer/pfsense-2.7/

Build automatisé du template pfSense via séquence de touches clavier simulées. Patche `config.xml` à chaud (interfaces vtnet, IP LAN `172.16.255.254/28`, DNS 1.1.1.1/8.8.8.8, SSH activé). Produit la template ID 9001 sur Proxmox.

### ansible/

| Playbook | Rôles | Cible | Déclencheur |
|---|---|---|---|
| `playbooks/services-vm.yml` | `base` | services-vm | Manuel |
| `playbooks/vault.yml` | `base`, `vault` | vault-vm | `npm run deploy` Phase 5 |

Le rôle `vault` installe Vault via le dépôt HashiCorp, configure le stockage Raft, init + unseal automatique (5 shares / threshold 3), sauvegarde les unseal keys dans `/root/vault-init.json` sur la VM et les rapatrie dans `ansible/vault-init.json`.

`ansible.cfg` configure le ProxyJump via `root@51.75.128.134` pour atteindre le LAN `172.16.0.0/24`. La clé SSH est injectée dans la VM via QEMU agent (API Proxmox) avant qu'Ansible se connecte — contournement du bug cloud-init + Ubuntu autoinstall.

---

## Réseau

### PVE1 — On-premise

| Élément | Valeur |
|---|---|
| Proxmox IP publique | `51.75.128.134` |
| Proxmox node | `proxmox-site1` |
| LAN réseau | `172.16.0.0/24` |
| LAN gateway | `172.16.0.254` |

| VM | ID | IP | Rôle |
|---|---|---|---|
| ubuntu-22.04-template | 9000 | — | Base clone (stopped) |
| pfsense-template | 9001 | — | Base clone pfSense (stopped) |
| pfsense-fw-01 | 1001 | `172.16.0.254` | Pare-feu LAN/WAN |
| vault-vm | 1200 | `172.16.0.242` | HashiCorp Vault |
| services-vm | 1100 | `172.16.0.241` | Netbox, website |

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
  ├── packer/**     → packer.yml    → packer build (template Ubuntu)
  └── terraform/**
      ansible/**    → deploy-onprem.yml
                         ├── terraform init + plan + apply
                         ├── attente SSH (timeout 120s par VM)
                         └── ansible-playbook vault.yml
```

Les deux workflows tournent sur un **self-hosted runner** installé sur le réseau Proxmox (accès direct aux IPs `172.16.255.x`).

---

## Décisions techniques

| Décision | Raison |
|---|---|
| Template Ubuntu via Terraform (pas Packer) | Plus simple, pas de dépendance à l'ISO, idempotent |
| Template pfSense via Packer | pfSense n'a pas de cloud-init — la config doit être injectée à l'install |
| Vault en mode Raft | Pas de dépendance externe (pas de Consul), single-node suffisant pour le lab |
| `bpg/proxmox` provider | Support complet cloud-init, download_file, et SSH pour import disque |
| Bootstrap Terraform séparé | Évite la dépendance circulaire token/permissions — tourne une seule fois avec root password |
