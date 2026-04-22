output "vm_id" {
  description = "Proxmox VM ID of the created template"
  value       = proxmox_virtual_environment_vm.template.vm_id
}
