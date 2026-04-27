output "services_vm_ip" {
  description = "Services VM IP address"
  value       = module.services_vm.ip_address
}

output "services_vm_id" {
  description = "Proxmox VM ID"
  value       = module.services_vm.vm_id
}

output "vault_vm_ip" {
  description = "Vault VM IP address"
  value       = module.vault_vm.ip_address
}

output "vault_vm_id" {
  description = "Vault VM Proxmox ID"
  value       = module.vault_vm.vm_id
}
