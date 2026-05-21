output "pfsense_vm_info" {
  description = "pfSense Firewall VM information"
  value = {
    vm_id      = module.pfsense.vm_id
    name       = module.pfsense.name
    ip_address = module.pfsense.ip_address
  }
}

output "elk_vault_vm_info" {
  description = "ELK Stack + Vault VM information"
  value = {
    vm_id      = module.elk_vault.vm_id
    name       = module.elk_vault.name
    ip_address = module.elk_vault.ip_address
  }
}

output "services_vm_info" {
  description = "Services VM (NetBox + Web) information"
  value = {
    vm_id      = module.services_vm.vm_id
    name       = module.services_vm.name
    ip_address = module.services_vm.ip_address
  }
}

# Legacy outputs for compatibility
output "services_vm_ip" {
  description = "Services VM IP address"
  value       = module.services_vm.ip_address
}

output "services_vm_id" {
  description = "Services VM Proxmox ID"
  value       = module.services_vm.vm_id
}

output "ops_vm_ip" {
  description = "ELK + Vault VM IP address"
  value       = module.elk_vault.ip_address
}

output "ops_vm_id" {
  description = "ELK + Vault VM Proxmox ID"
  value       = module.elk_vault.vm_id
}
