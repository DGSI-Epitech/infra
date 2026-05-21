# Module vm-proxmox - Base VM Creation

Module Terraform pour la création de machines virtuelles sur Proxmox à partir d'un template cloud-init.

## Usage

```hcl
module "my_vm" {
  source = "../../modules/vm-proxmox"

  # Identité
  proxmox_node    = "pve"
  name            = "my-vm"
  vm_id           = 100
  template_vm_id  = 99

  # Ressources (CPU, RAM, Disque)
  vm_cores        = 2
  vm_memory_mb    = 2048
  disk_size_gb    = 20
  storage_vm      = "local-lvm"

  # Réseau
  network_bridge  = "vmbr0"
  network_tag     = 0           # VLAN tag ou 0 pour non-tagué
  vm_ip_cidr      = "192.168.100.50/24"
  vm_gateway      = "192.168.100.1"

  # Cloud-Init
  vm_ssh_public_key = "ssh-rsa AAAA..."
  cloud_init_script  = null      # Optionnel: custom user-data

  # Organisation
  tags            = ["app", "production"]
}
```

## Variables Requises

- `proxmox_node`: Nom du nœud Proxmox
- `name`: Nom de la VM
- `vm_id`: ID unique dans Proxmox
- `template_vm_id`: ID du template à cloner
- `storage_vm`: Storage Proxmox pour les disques VM
- `network_bridge`: Bridge virtuel (ex: vmbr0)
- `vm_ip_cidr`: IP en format CIDR (ex: 192.168.100.50/24)
- `vm_gateway`: Gateway par défaut
- `vm_ssh_public_key`: Clé SSH pour cloud-init

## Variables Optionnelles

- `vm_cores`: Nombre de cores CPU (défaut: 2)
- `vm_memory_mb`: RAM en MB (défaut: 2048)
- `disk_size_gb`: Taille disque en GB (défaut: 20)
- `network_tag`: VLAN tag (défaut: null = non-tagué)
- `cloud_init_script`: Script cloud-init personnalisé
- `tags`: Tags pour l'organisation

## Outputs

- `vm_id`: ID Proxmox de la VM
- `name`: Nom de la VM
- `node_name`: Nœud Proxmox
- `ip_address`: Adresse IP configurée

## Ressources Créées

- `proxmox_virtual_environment_vm`: Machine virtuelle Ubuntu clonée depuis template
- Configuration cloud-init automatique (hostname, SSH keys, IP, gateway)

## Notes

- Le clone du template est complet (`full = true`) pour isolation complète
- Cloud-init configure automatiquement le hostname et la clé SSH
- Les changements cloud-init après création sont ignorés (lifecycle)
- Le provider Proxmox doit être configuré au niveau du workspace
