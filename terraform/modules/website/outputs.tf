output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.website.vm_id
}

output "ip_address" {
  description = "Website static IP address (CIDR)"
  value       = var.vm_ip_cidr
}
