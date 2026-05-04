output "services_vm_ip" {
  description = "Services VM IP address"
  value       = module.services_vm.ip_address
}

output "services_vm_id" {
  description = "Proxmox VM ID"
  value       = module.services_vm.vm_id
}

output "ops_vm_ip" {
  description = "Ops VM IP address"
  value       = module.ops_vm.ip_address
}

output "ops_vm_id" {
  description = "Ops VM Proxmox ID"
  value       = module.ops_vm.vm_id
}
