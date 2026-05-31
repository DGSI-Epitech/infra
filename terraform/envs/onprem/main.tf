module "services_vm" {
  source = "../../modules/services-vm"

  proxmox_node      = var.proxmox_node
  vm_id             = var.services_vm_id
  template_vm_id    = var.template_ubuntu_vm_id
  vm_ssh_public_key = var.vm_ssh_public_key
  storage_iso       = var.storage_iso
  storage_vm        = var.storage_vm
}

module "ops_vm" {
  source = "../../modules/ops-vm"
  proxmox_node      = var.proxmox_node
  template_vm_id    = var.template_ubuntu_vm_id
  vm_id             = var.ops_vm_id
  vm_ssh_public_key = var.vm_ssh_public_key
  storage_iso       = var.storage_iso
  storage_vm        = var.storage_vm
  vm_cores          = 4
  vm_memory_mb      = 8192
  disk_size_gb      = 30
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