module "ubuntu_template" {
  source = "../../modules/ubuntu-template"

  proxmox_node = var.proxmox_node
  vm_id        = var.template_vm_id
  storage_iso  = var.storage_iso
  storage_vm   = var.storage_vm
}

module "services_vm" {
  source = "../../modules/services-vm"

  proxmox_node      = var.proxmox_node
  template_vm_id    = module.ubuntu_template.vm_id
  vm_ip_cidr        = var.vm_ip_cidr
  vm_gateway        = var.vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
}

module "vault_vm" {
  source = "../../modules/vault-vm"

  proxmox_node      = var.proxmox_node
  template_vm_id    = module.ubuntu_template.vm_id
  vm_id             = var.vault_vm_id
  vm_ip_cidr        = var.vault_vm_ip_cidr
  vm_gateway        = var.vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
}

module "pfsense" {
  source = "../../modules/pfsense"

  proxmox_node    = var.proxmox_node
  template_vm_id  = 9001   
  # Adressage réseau issu de tes documents pour le Site 1
  lan_bridge      = "vmbr1" # Ton bridge LAN interne
  wan_bridge      = "vmbr0" # Ton bridge WAN (accès internet)
  
  vm_name         = "pfsense-fw-01"
}