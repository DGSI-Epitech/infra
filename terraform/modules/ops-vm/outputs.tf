output "ip_address" {
  description = "Ops VM IP address (assigned by DHCP)"
  value       = proxmox_virtual_environment_vm.ops_vm.ipv4_addresses
}

output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.ops_vm.vm_id
}
