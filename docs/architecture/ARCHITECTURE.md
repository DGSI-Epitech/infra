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
          │  ops-vm         │                              │  website            │
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
    ├─► Clone Ubuntu template  → services-vm (ID 2300) + cloud-init DHCP
    └─► Clone Ubuntu template  → ops-vm (ID 2200) + cloud-init DHCP + 30 Go disque

  deploy.sh
    ├─► Extension partition disque (growpart + pvresize + lvextend + resize2fs)
    └─► Ansible (inventory/onprem.py — dynamique depuis config.env)
          ├─► roles/base    → Docker, UFW, paquets de base (toutes les VMs)
          ├─► roles/vault   → HashiCorp Vault (container Docker standalone)
          ├─► roles/elk     → ELK stack (Docker Compose : Elasticsearch + Logstash + Kibana)
          └─► roles/filebeat → Filebeat sur services-vm (envoi logs vers Logstash)
```

---

## Composants

### terraform/envs/bootstrap/

Tourne **une seule fois** sur un Proxmox vierge. S'authentifie avec `root@pam` username/password, crée le rôle `TerraformRole` avec les privileges nécessaires, génère le token `root@pam!terraform` et lui assigne le rôle. Output : le token à injecter dans `TF_VAR_proxmox_api_token`.

### terraform/envs/onprem/

Environnement principal PVE1. Appelle quatre modules :

| Module | Ressource créée | ID Proxmox | Disque |
|---|---|---|---|
| `pfsense` | Clone le template pfSense Packer | 2100 | — |
| `services-vm` | Clone le template Ubuntu, DHCP | 2300 | 20 Go |
| `ops-vm` | Clone le template Ubuntu, DHCP | 2200 | 30 Go |

`ops-vm` a un disque plus large (30 Go) pour héberger les images Docker ELK (~4-5 Go) en plus de Vault.

### packer/pfsense-2.7/

Build automatisé du template pfSense via séquence de touches clavier simulées. Injecte `config.xml.pkrtpl.hcl` (template Packer) via un CD virtuel — contient les interfaces vtnet, IP LAN `172.16.0.254/24`, DNS, SSH activé, et la clé SSH publique admin. Produit le template ID 2000 sur Proxmox.

### packer/ubuntu-22.04/

Build automatisé du template Ubuntu 22.04 via autoinstall. Utilise un password éphémère (généré dans deploy.sh, jamais stocké) pour le communicator SSH. Injecte la clé SSH via provisioner, désactive le password SSH, nettoie le template. Produit le template ID 1000 sur Proxmox.

### ansible/

| Playbook | Rôles | Cible | Port(s) |
|---|---|---|---|
| `playbooks/vault.yml` | `base`, `vault` | ops-vm | 8200 |
| `playbooks/elk.yml` | `elk` | ops-vm | 9200, 9300, 5601, 5044 |
| `playbooks/filebeat.yml` | `filebeat` | services-vm | — |

L'inventaire `inventory/onprem.py` est un script Python dynamique qui lit `config.env`. Les IPs, la clé SSH et le ProxyJump SSH (via Proxmox) sont toujours cohérents avec l'environnement déployé.

#### Rôle `vault`

Installe HashiCorp Vault en **container Docker standalone** (`hashicorp/vault:latest`). Configure le storage Raft local (`/opt/vault/data`), le listener TCP sur `0.0.0.0:8200`. Init + unseal automatique via le rôle Ansible ; les unseal keys sont sauvegardées dans `/root/vault-init.json` sur ops-vm.

#### Rôle `elk`

Déploie la stack ELK via **Docker Compose** dans `/opt/elk`. Trois containers :

| Container | Image | Port |
|---|---|---|
| `elasticsearch` | `elasticsearch:8.13.0` | 9200 (API), 9300 (cluster) |
| `logstash` | `logstash:8.13.0` | 5044 (Beats input) |
| `kibana` | `kibana:8.13.0` | 5601 (UI web) |

Elasticsearch et Logstash partagent un réseau Docker `elk-net`. Kibana et Logstash démarrent uniquement après le healthcheck Elasticsearch (`/_cluster/health?status=green`). `vm.max_map_count` est fixé à `262144` via `sysctl` (requis par Elasticsearch).

#### Rôle `filebeat`

Installe Filebeat via le dépôt apt Elastic sur `services-vm`. Collecte les logs système (`/var/log/syslog`) et les logs des containers Docker (`/var/lib/docker/containers/**/*.log`). Les envoie à Logstash (port 5044) sur ops-vm, dont l'IP est résolue dynamiquement via `hostvars`.

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
| pfsense-fw-01 | 2100 | `172.16.0.254` | Pare-feu LAN/WAN, DHCP |
| services-vm | 2300 | DHCP `172.16.0.241` | Netbox, website, Filebeat |
| ops-vm | 2200 | DHCP `172.16.0.242` | Vault + ELK (ES + Logstash + Kibana) |

### Ports exposés sur ops-vm (UFW)

| Port | Service | Accessible depuis |
|---|---|---|
| 8200 | Vault API | LAN + tunnel SSH |
| 9200 | Elasticsearch API | LAN interne |
| 9300 | Elasticsearch cluster | LAN interne |
| 5601 | Kibana UI | LAN + tunnel SSH |
| 5044 | Logstash Beats input | services-vm |

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
                               ├── vault.yml   → ops-vm
                               ├── elk.yml     → ops-vm
                               └── filebeat.yml → services-vm
```

Les deux workflows tournent sur un **self-hosted runner** installé sur le réseau Proxmox (accès direct aux IPs `172.16.0.x`).

---

## Décisions techniques

| Décision | Raison |
|---|---|
| Template Ubuntu via Packer | Contrôle total du build — password éphémère, clé SSH injectée par provisioner |
| Template pfSense via Packer | pfSense n'a pas de cloud-init — config injectée via CD (config.xml template) |
| Vault en container Docker standalone | Isolation du process, redémarrage automatique, pas de dépendance système |
| ELK via Docker Compose | Orchestration des dépendances (ES healthcheck → Logstash/Kibana), volumes persistants, rollback simple |
| Vault + ELK sur la même VM (ops-vm) | Mutualisation des ressources sur un lab mono-site, même réseau Docker |
| Vault et ELK en containers séparés | Isolation des processus, redémarrage indépendant, pas de Docker-in-Docker |
| `bpg/proxmox` provider | Support cloud-init, download_file, SSH pour import disque |
| Bootstrap Terraform séparé | Évite la dépendance circulaire token/permissions — tourne une seule fois |
| Inventaire Ansible dynamique (Python) | IPs et ProxyJump toujours cohérents avec config.env, pas de duplication |
| QEMU agent pour injection clé SSH | cloud-init ne met pas à jour authorized_keys pour un user créé par autoinstall |
| ProxyJump Proxmox pour Ansible | VMs sur vmbr1 (réseau privé), inaccessibles directement depuis l'extérieur |
| growpart dans deploy.sh | cloud-init ne redimensionne pas automatiquement la partition sur un clone Ubuntu LVM |
