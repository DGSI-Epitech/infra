output "bastion_vm_id" {
  description = "Proxmox VM ID of the bastion"
  value       = module.bastion.vm_id
}

output "bastion_ip" {
  description = "Bastion IP address (DMZ)"
  value       = module.bastion.ip_address
}

output "website_vm_id" {
  description = "Proxmox VM ID of the website"
  value       = module.website.vm_id
}

output "website_ip" {
  description = "Website IP address (LAN Cloud)"
  value       = module.website.ip_address
}
