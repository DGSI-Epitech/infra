module "services_vm" {
  source = "../../modules/services-vm"

  proxmox_node      = var.proxmox_node
  vm_id             = var.services_vm_id
  template_vm_id    = var.template_ubuntu_vm_id
  vm_ip_cidr        = var.vm_ip_cidr
  vm_gateway        = var.vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
  vm_password       = var.vm_password
  storage_iso       = var.storage_iso
  storage_vm        = var.storage_vm
}

module "vault_vm" {
  source = "../../modules/vault-vm"
  proxmox_node      = var.proxmox_node
  template_vm_id    = var.template_ubuntu_vm_id
  vm_id             = var.vault_vm_id
  vm_ip_cidr        = var.vault_vm_ip_cidr
  vm_gateway        = var.vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
  vm_password       = var.vm_password
  storage_iso       = var.storage_iso
  storage_vm        = var.storage_vm
}

module "pfsense" {
  source = "../../modules/pfsense"

  proxmox_node   = var.proxmox_node
  vm_id          = var.pfsense_vm_id
  template_vm_id = var.pfsense_template_id
  lan_bridge     = "vmbr1"
  wan_bridge     = "vmbr2"
  vm_name        = "pfsense-fw-01"
}