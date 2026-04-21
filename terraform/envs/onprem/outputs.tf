output "services_vm_ip" {
  description = "Services VM IP address"
  value       = module.services_vm.ip_address
}

output "services_vm_id" {
  description = "Proxmox VM ID"
  value       = module.services_vm.vm_id
}
