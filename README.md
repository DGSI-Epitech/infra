# School Infra

Infrastructure as Code pour un lab homelab/école déployé sur deux sites Proxmox.

Tout est automatisé : une commande Terraform crée les VMs, Ansible les configure. Objectif : lab fonctionnel en moins de 10 minutes sur un environnement vierge.

---

## Stack technique

| Outil | Rôle |
|---|---|
| **Terraform** | Crée les VMs sur Proxmox (template Ubuntu + clones) |
| **Ansible** | Configure les services sur les VMs (Vault, Docker, etc.) |
| **Packer** | Build la template Ubuntu de base (optionnel, déclenché par CI) |
| **GitHub Actions** | CI/CD — déploie automatiquement sur push |

---

## Prérequis

- Git
- Terraform ≥ 1.9 (`npm run setup` l'installe automatiquement)
- Ansible (`pip install ansible`)
- Une paire de clés SSH (`~/.ssh/id_ed25519`)
- Accès à l'interface web Proxmox

---

## Avant de commencer — Proxmox à configurer (une seule fois)

> Ces étapes sont nécessaires uniquement au premier déploiement ou sur un Proxmox vierge.
> Pour le détail complet avec captures d'écran : voir [`docs/runbooks/RUNBOOKS.md`](docs/runbooks/RUNBOOKS.md)

**1. Créer un token API Terraform dans Proxmox**

Dans l'interface web Proxmox :
- Datacenter → Permissions → API Tokens → Add
- User : `root@pam`, Token ID : `terraform`, décocher "Privilege Separation"
- Copier le secret affiché (visible une seule fois)
- Ajouter la permission : Datacenter → Permissions → Add → API Token Permission → path `/`, rôle `Administrator`

**2. Autoriser ta clé SSH sur Proxmox** (nécessaire pour l'import des disques)

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<IP_PROXMOX>
ssh-add ~/.ssh/id_ed25519
```

---

## Déploiement

### 1. Cloner et configurer

```bash
git clone <repo>
cd infra

# Installer Terraform
npm run setup

# Copier et remplir les variables
cp terraform/envs/onprem/terraform.tfvars.example terraform/envs/onprem/terraform.tfvars
# Édite le fichier avec tes vraies valeurs (IP, gateway, clé SSH publique)
```

### 2. Injecter le token Proxmox

```bash
# Utilise des guillemets simples — obligatoire à cause du ! dans le token
export TF_VAR_proxmox_api_token='root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

### 3. Déployer les VMs

```bash
cd terraform/envs/onprem
terraform init
terraform plan
terraform apply
```

Terraform va :
1. Télécharger l'image Ubuntu 22.04 cloud sur Proxmox (~660 MB, une seule fois)
2. Créer la VM template (ID 9000)
3. Cloner la template → services-vm (ID 200) et vault-vm (ID 201)
4. Injecter l'IP statique et la clé SSH via cloud-init

### 4. Configurer les services avec Ansible

Une fois les VMs démarrées (attendre ~2 min après `terraform apply`) :

```bash
cd ansible
ansible-playbook playbooks/vault.yml -i inventory/onprem.yml
```

---

## Variables importantes (terraform.tfvars)

| Variable | Description | Valeur PVE1 |
|---|---|---|
| `proxmox_endpoint` | URL de l'API Proxmox | `https://192.168.139.128:8006` |
| `proxmox_node` | Nom du nœud Proxmox | `pve` |
| `proxmox_node_address` | IP Proxmox pour SSH | `192.168.139.128` |
| `template_vm_id` | ID de la VM template | `9000` |
| `vm_ip_cidr` | IP de services-vm | `172.16.255.242/28` |
| `vault_vm_ip_cidr` | IP de vault-vm | `172.16.255.243/28` |
| `vm_gateway` | Passerelle du réseau LAN | `172.16.255.254` |
| `vm_ssh_public_key` | Clé publique SSH (`cat ~/.ssh/id_ed25519.pub`) | `ssh-ed25519 AAAA...` |

---

## CI/CD (GitHub Actions)

Deux workflows automatiques :

| Workflow | Déclencheur | Action |
|---|---|---|
| `packer.yml` | Push sur `packer/**` ou manuel | Build la template Ubuntu sur Proxmox |
| `deploy-onprem.yml` | Push sur `terraform/**` ou `ansible/**` | Terraform apply + Ansible |

Les workflows nécessitent un **self-hosted runner** sur le réseau Proxmox.

Secrets GitHub à configurer :

| Secret | Valeur |
|---|---|
| `PROXMOX_API_TOKEN` | `root@pam!terraform=<uuid>` |
| `PROXMOX_PACKER_TOKEN` | `root@pam!packer=<uuid>` |
| `PACKER_BUILD_PASSWORD` | Mot de passe de build Packer |
| `PACKER_BUILD_PASSWORD_ENCRYPTED` | Hash SHA-512 du mot de passe |
| `ANSIBLE_SSH_PRIVATE_KEY_PATH` | Chemin de la clé SSH sur le runner |

---

## Sécurité

- Aucun secret dans le dépôt
- Les tokens sont injectés via variables d'environnement ou secrets CI/CD
- `*.tfstate`, `*.tfvars` et `*.pkrvars.hcl` sont ignorés par git
- `vault-init.json` (unseal keys) est ignoré par git
- Toute modification passe par une Pull Request

---

## Structure du projet

```
infra/
├── terraform/
│   ├── envs/
│   │   └── onprem/          # Environnement on-prem (PVE1)
│   └── modules/
│       ├── ubuntu-template/ # Télécharge l'image et crée la template
│       ├── services-vm/     # VM services (Netbox, Docker...)
│       └── vault-vm/        # VM HashiCorp Vault
├── ansible/
│   ├── inventory/
│   │   └── onprem.yml       # Inventaire des VMs
│   ├── playbooks/
│   │   └── vault.yml        # Déploie et initialise Vault
│   └── roles/
│       └── vault/           # Rôle Ansible pour Vault
├── packer/
│   └── ubuntu-22.04/        # Build de la template (optionnel)
├── .github/workflows/       # CI/CD GitHub Actions
└── docs/                    # Documentation et runbooks
```

Pour le détail des problèmes rencontrés et leur résolution : [`docs/runbooks/RUNBOOKS.md`](docs/runbooks/RUNBOOKS.md)
