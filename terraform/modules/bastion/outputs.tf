output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.bastion.vm_id
}

output "ip_address" {
  description = "Bastion static IP address (CIDR)"
  value       = var.vm_ip_cidr
}
