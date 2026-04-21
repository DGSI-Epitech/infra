module "services_vm" {
  source = "../../modules/services-vm"

  proxmox_node      = var.proxmox_node
  vm_ip_cidr        = var.vm_ip_cidr
  vm_gateway        = var.vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
}
