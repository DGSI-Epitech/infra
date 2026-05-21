output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "name" {
  description = "VM name"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "node_name" {
  description = "Proxmox node name"
  value       = proxmox_virtual_environment_vm.vm.node_name
}

output "ip_address" {
  description = "VM IP address"
  value       = var.vm_ip_cidr
}
