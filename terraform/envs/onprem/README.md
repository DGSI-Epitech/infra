# Environnement On-Prem - Déploiement Proxmox

Déploiement de 3 machines virtuelles sur le Proxmox du site on-premises.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SITE ON-PREM (Proxmox)                   │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────────┐│
│  │  pfSense-FW  │  │  ELK + Vault    │  │  Services (NB+W) ││
│  │  (Firewall)  │  │  (Monitoring)   │  │  (Infrastructure)││
│  │              │  │                 │  │                  ││
│  │ ID: 101      │  │ ID: 102         │  │ ID: 103          ││
│  │ 2 CPU, 2GB   │  │ 4 CPU, 8GB      │  │ 4 CPU, 8GB       ││
│  │ 20GB disk    │  │ 50GB disk       │  │ 50GB disk        ││
│  │              │  │                 │  │                  ││
│  │ 192.168.100.1│  │ 192.168.100.2   │  │ 192.168.100.3    ││
│  └──────────────┘  └─────────────────┘  └──────────────────┘│
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## VMs

### 1. pfSense Firewall (ID: 101)
- **Rôle**: Pare-feu, gateway réseau
- **Template**: pfSense (Packer)
- **Specs**:
  - CPU: 2 cores
  - RAM: 2 GB
  - Disque: 20 GB
  - IP: 192.168.100.1/24
- **Dépendances**: Aucune (première à démarrer)

### 2. ELK Stack + Vault (ID: 102)
- **Rôle**: Monitoring, logging, gestion des secrets
- **Template**: Ubuntu 22.04
- **Services**:
  - Elasticsearch - Indexation des logs
  - Kibana - Visualisation des logs
  - Logstash - Pipelines de traitement
  - Filebeat - Collection des logs
  - Vault Hashicorp - Gestion centralisée des secrets
- **Specs**:
  - CPU: 4 cores
  - RAM: 8 GB
  - Disque: 50 GB
  - IP: 192.168.100.2/24
- **Dépendances**: pfSense
- **Ports**:
  - Elasticsearch: 9200
  - Kibana: 5601
  - Vault: 8200

### 3. Services VM (ID: 103)
- **Rôle**: Infrastructure management, web services
- **Template**: Ubuntu 22.04
- **Services**:
  - NetBox - IPAM + DCIM
  - Nginx/Apache - Web services
  - Support pour applications futures
- **Specs**:
  - CPU: 4 cores
  - RAM: 8 GB
  - Disque: 50 GB
  - IP: 192.168.100.3/24
- **Dépendances**: ELK Stack
- **Ports**:
  - NetBox: 8080

## Fichiers de Configuration

### Variables (variables.tf)
- Informations Proxmox (API, nœud, stockage)
- IDs des templates et VMs
- Configuration réseau (bridge, VLAN)
- Spécifications des VMs (CPU, RAM, disque)
- IPs et gateways

### Values (terraform.tfvars)
Voir `terraform.tfvars.example` pour template complet.

### Outputs (outputs.tf)
- `pfsense_vm_info`: ID, nom, IP de pfSense
- `elk_vault_vm_info`: ID, nom, IP d'ELK+Vault
- `services_vm_info`: ID, nom, IP de Services
- Outputs legacy pour compatibilité

## Déploiement

### 1. Configuration
```bash
cd terraform/envs/onprem
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars avec les valeurs réelles
```

### 2. Plan
```bash
terraform plan
```

### 3. Apply
```bash
terraform apply
```

### 4. Résultats
Les outputs affichent les informations des VMs créées.

## Post-Déploiement

Après le déploiement Terraform des VMs, utiliser Ansible pour:
1. Configuration de pfSense (pare-feu, NAT, routes)
2. Installation de ELK + Vault
3. Installation de NetBox + web services

Voir la documentation Ansible dans `ansible/playbooks/`

## Ordre de Déploiement

Les dépendances Terraform assurent l'ordre correct:
1. pfSense Firewall
2. ELK + Vault (après pfSense)
3. Services (après ELK+Vault)

## Modification des Spécifications

Chaque VM a ses propres variables (ex: `pfsense_cores`, `elk_memory_mb`, `services_disk_size_gb`) pour permettre l'ajustement indépendant des ressources.

## Troubleshooting

### Erreur: "VM ID already in use"
Vérifier les IDs dans terraform.tfvars ne chevauchent pas les VMs existantes.

### Cloud-init ne configure pas l'IP
Les changements cloud-init après création sont ignorés. Utiliser Ansible pour modifications post-création.

### Problèmes de réseau
- Vérifier `network_bridge` corresponds au bridge Proxmox
- Vérifier les IPs ne chevauchent pas
- Vérifier la gateway est accessible
