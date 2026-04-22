variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID for the template"
  type        = number
  default     = 9000
}

variable "storage_iso" {
  description = "Proxmox storage for the cloud image download"
  type        = string
  default     = "local"
}

variable "storage_vm" {
  description = "Proxmox storage for the VM disk"
  type        = string
  default     = "local-lvm"
}
