output "ip_address" {
  description = "Vault VM IP address"
  value       = split("/", var.vm_ip_cidr)[0]
}

output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.vault_vm.vm_id
}
