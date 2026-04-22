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
