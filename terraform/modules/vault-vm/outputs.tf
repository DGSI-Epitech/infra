output "ip_address" {
  description = "Vault VM IP address (assigned by DHCP)"
  value       = proxmox_virtual_environment_vm.vault_vm.ipv4_addresses
}

output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.vault_vm.vm_id
}
