# Terraform Infrastructure-as-Code

Infrastructure complète en Terraform pour déploiement multi-cloud (on-premises + cloud).

## Structure

```
terraform/
├── locals.tf              # Variables locales partagées
├── providers.tf           # Configuration des providers partagés
├── versions.tf            # Versions requises
├── envs/                  # Environnements
│   ├── bootstrap/         # Infrastructure d'amorçage
│   ├── onprem/           # Site on-premises (Proxmox)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── versions.tf
│   │   ├── backend.tf
│   │   ├── terraform.tfvars
│   │   ├── terraform.tfvars.example
│   │   └── README.md
│   └── remote/            # Infrastructure cloud
└── modules/               # Modules réutilisables
    ├── vm-proxmox/        # Module base: création VM Ubuntu
    ├── pfsense/           # Module pfSense firewall
    ├── bastion/           # Module bastion/jumphost
    ├── netbox/            # Module NetBox (IPAM)
    ├── siem/              # Module stack ELK+Vault
    └── ...
```

## Modules Disponibles

### vm-proxmox
Module base pour créer des VMs Ubuntu clonées d'un template cloud-init.

**Inputs**:
- Infos VM: name, vm_id, proxmox_node
- Ressources: cores, memory_mb, disk_size_gb
- Réseau: network_bridge, network_tag, ip_cidr, gateway
- Cloud-init: ssh_public_key, custom_script

**Outputs**:
- vm_id, name, node_name, ip_address

Voir [modules/vm-proxmox/README.md](modules/vm-proxmox/README.md)

### pfsense
Déploiement et configuration de pfSense comme pare-feu/gateway.

### siem
Stack ELK + Vault Hashicorp pour monitoring et gestion des secrets.

### bastion
Machine bastion pour accès SSH sécurisé aux ressources internes.

### netbox
Déploiement de NetBox pour IPAM et DCIM.

## Environnements

### onprem
Déploiement Proxmox du site on-premises avec 3 VMs:
1. **pfSense** (101) - Firewall/gateway
2. **ELK+Vault** (102) - Monitoring et secrets
3. **Services** (103) - NetBox et web services

Configuration: `terraform/envs/onprem/`

Voir [envs/onprem/README.md](envs/onprem/README.md)

### remote
Infrastructure cloud (AWS/Azure/etc) - À définir

### bootstrap
Infrastructure d'amorçage (pas d'état cloud) - À définir

## Utilisation

### 1. Setup Initial

```bash
# Installer Terraform 1.5+
terraform version

# Cloner le repo
git clone <repo>
cd infra/terraform
```

### 2. Déploiement On-Prem

```bash
cd envs/onprem

# Éditer la configuration
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars avec les vraies valeurs

# Valider la syntaxe
terraform validate

# Voir le plan de déploiement
terraform plan

# Appliquer les changements
terraform apply

# Voir les outputs
terraform output
```

### 3. Destruction (si besoin)

```bash
cd envs/onprem
terraform destroy
```

## Provider: Proxmox

Les modules on-prem utilisent le provider Proxmox [bpg/proxmox](https://github.com/bpg/terraform-provider-proxmox).

**Configuration requise** (dans `envs/onprem/providers.tf`):
- Endpoint API Proxmox
- Token d'authentification
- Clé SSH pour accès root (cloud-init disk import)

## Provider: pfSense

Module pfSense utilise le provider [RBEI/pfsense](https://github.com/RBEI/terraform-provider-pfsense).

## Bonnes Pratiques

### Secrets
- Ne JAMAIS commiter `terraform.tfvars` (fichier réel)
- Utiliser `terraform.tfvars.example` pour template
- Stocker les secrets dans Vault/1Pass pendant le déploiement

### État
- Backend S3/Azurerm recommandé pour équipes
- État local acceptable pour single-user dev
- Toujours faire backup de l'état

### Tags et Naming
- Tous les modules appliquent des tags pour organisation
- Noms uniformes: `{component}-{environment}-{number}`
- Exemples: `pfsense-fw-01`, `elk-vault-01`, `services-vm-01`

### Modularité
- Chaque VM peut être déployée indépendamment avec ses variables
- Utiliser `depends_on` pour ordre de déploiement
- Modules sans état cloud pour une meilleure réutilisabilité

## Architecture Multi-Environnement

**Environnements**:
- `onprem`: Production on-premises (Proxmox)
- `remote`: Infrastructure cloud
- `bootstrap`: Amorçage (infrastructure minimale)

**Séparation d'état**: Chaque environnement a son propre état Terraform.

## Terraform Workspaces (Optionnel)

```bash
# Créer un workspace
terraform workspace new staging

# Lister workspaces
terraform workspace list

# Sélectionner workspace
terraform workspace select staging
```

## Troubleshooting

### Erreur de validation
```bash
terraform validate
```

### Voir plan détaillé
```bash
terraform plan -out=plan.tfplan
terraform show plan.tfplan
```

### Debug
```bash
export TF_LOG=DEBUG
terraform apply
```

### Importer une ressource existante
```bash
terraform import module.name.resource_type.name proxmox_id
```

## Voir Aussi

- [Ansible](../ansible/) - Configuration des VMs post-déploiement
- [Packer](../packer/) - Création des templates VM
- Architecture: [docs/architecture/](../docs/architecture/)
- Décisions: [docs/decisions/](../docs/decisions/)
