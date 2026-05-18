# School Infra

Infrastructure as Code pour un lab école déployé sur Proxmox (site on-premise).

Tout est automatisé : une commande déploie pfSense, les templates et les VMs. Objectif : lab fonctionnel en moins de 15 minutes sur un environnement vierge.

---

## Stack technique

| Outil | Rôle |
|---|---|
| **Packer** | Build la template pfSense 2.7.2 sur Proxmox |
| **Terraform** | Crée les VMs (template Ubuntu + pfSense + clones) |
| **Ansible** | Configure les services sur les VMs (Vault, etc.) |
| **GitHub Actions** | CI/CD — déploie automatiquement sur push |

---

## Prérequis

- Node.js (pour `npm run`)
- Terraform ≥ 1.9 (`npm run setup` l'installe)
- Packer ≥ 1.11
- Ansible (`pip install ansible`)
- Accès SSH root au Proxmox
- Une paire de clés SSH ED25519 (voir section ci-dessous)

### Générer et configurer la clé SSH

L'infrastructure n'utilise **aucun password** pour accéder aux VMs. Une unique paire de clés SSH couvre tous les accès : Packer (communicator + bastion), Terraform (provider bpg), Ansible (pfSense, vault-vm, services-vm).

```bash
# 1. Générer la paire de clés (si elle n'existe pas déjà)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "lab-infra"

# 2. Copier la clé publique sur Proxmox
#    Requis pour : Packer bastion SSH + Terraform provider bpg disk import
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<PROXMOX_HOST>

# 3. Ajouter la clé à l'agent SSH pour la session courante
ssh-add ~/.ssh/id_ed25519

# 4. Vérifier la connexion
ssh root@<PROXMOX_HOST> echo "OK"
```

Ces valeurs sont ensuite reportées dans `config.env` :

```bash
SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"
```

---

## Démarrage rapide

### 1. Configurer

```bash
git clone <repo> && cd infra
npm run setup                          # installe Terraform

# Clé SSH — voir section Prérequis
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "lab-infra"   # si elle n'existe pas
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<PROXMOX_HOST>
ssh-add ~/.ssh/id_ed25519

cp config.env.example config.env
# Remplir config.env — notamment :
#   PROXMOX_HOST, PROXMOX_PASSWORD, PROXMOX_NODE
#   SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
#   SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"

cp terraform/envs/onprem/terraform.tfvars.example terraform/envs/onprem/terraform.tfvars
# Remplir terraform.tfvars (IPs des VMs)
```

### 2. Déployer

```bash
npm run deploy
```

Le script fait dans l'ordre :
1. Authentification Proxmox via API
2. Suppression des VMs existantes (pfSense, services, vault)
3. Création du bridge LAN `vmbr1` si absent
4. Build Packer de la template pfSense (si absente)
5. `terraform apply` — template Ubuntu + pfSense VM + services-vm + vault-vm

### 3. Configurer les services

Une fois les VMs démarrées :

```bash
cd ansible
ansible-playbook playbooks/vault.yml -i inventory/onprem.py
```

### 4. Tout supprimer

```bash
npm run destroy
```

---

## config.env — Source de vérité

`config.env` centralise toutes les valeurs partagées entre Packer, Terraform et les scripts.
Il est gitignored — ne jamais le committer.

```bash
# Proxmox
PROXMOX_HOST="X.X.X.X"          # IP du serveur Proxmox
PROXMOX_USER="root@pam"
PROXMOX_PASSWORD="..."           # mot de passe root Proxmox (API uniquement)
PROXMOX_NODE="proxmox-site1"     # nom du nœud dans Proxmox
PROXMOX_STORAGE_VM="local"       # storage pour les disques VM

# VM IDs
VM_ID_UBUNTU_TEMPLATE=9000       # template Ubuntu (Terraform)
VM_ID_PFSENSE_TEMPLATE=9001      # template pfSense (Packer)
VM_ID_PFSENSE=1001               # VM pfSense déployée
VM_ID_SERVICES=1003              # VM services (Netbox, etc.)
VM_ID_VAULT=1002                 # VM HashiCorp Vault

# SSH — aucun password sur les VMs, clé SSH uniquement
SSH_PUBLIC_KEY="ssh-ed25519 AAAA..."       # cat ~/.ssh/id_ed25519.pub
SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"  # clé privée correspondante
```

> Pour passer à Vault comme source de vérité à la place de `config.env` : remplacer le `source "$CONFIG_FILE"` dans les scripts par des appels `vault kv get`.

---

## Infrastructure réseau

### PVE1 — On-premise

| Élément | Valeur |
|---|---|
| Proxmox IP | `51.75.128.134` |
| Proxmox node | `proxmox-site1` |
| pfSense WAN | `vmbr0` (interface physique) |
| pfSense LAN | `vmbr1` — `172.16.255.254/28` |
| Réseau LAN | `172.16.255.240/28` |

| VM | ID | IP | Bridge |
|---|---|---|---|
| ubuntu-template | 9000 | — | — |
| pfsense-template | 9001 | — | — |
| pfsense-fw-01 | 1001 | 172.16.255.254 (LAN) | vmbr0 + vmbr1 |
| services-vm | 1003 | 172.16.255.242/28 | vmbr1 |
| vault-vm | 1002 | 172.16.255.243/28 | vmbr1 |

---

## Structure du projet

```
infra/
├── config.env              # Config locale — gitignored
├── config.env.example      # Template à copier
├── scripts/
│   ├── deploy.sh           # Déploiement complet (Packer + Terraform)
│   └── destroy.sh          # Suppression de toutes les VMs
├── packer/
│   └── pfsense-2.7/        # Build template pfSense
├── terraform/
│   ├── envs/onprem/        # Environnement on-prem
│   └── modules/
│       ├── ubuntu-template/
│       ├── pfsense/
│       ├── services-vm/
│       └── vault-vm/
├── ansible/
│   ├── inventory/onprem.py
│   ├── playbooks/vault.yml
│   └── roles/vault/
└── docs/
    └── runbooks/RUNBOOKS.md
```

---

## Commandes utiles

| Commande | Description |
|---|---|
| `npm run deploy` | Déploiement complet |
| `npm run destroy` | Suppression de toutes les VMs |
| `npm run tf:plan:onprem` | Voir les changements Terraform sans appliquer |
| `npm run tf:fmt` | Formater les fichiers Terraform |
| `npm run tf:check` | Valider les configs Terraform |
