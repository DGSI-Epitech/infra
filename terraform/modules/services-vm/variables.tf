variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
  default     = 200
}

variable "vm_ip_address" {
  description = "Static IP address for the VM"
  type        = string
  default     = "172.16.0.241"
}

variable "vm_gateway" {
  description = "Default gateway for the VM"
  type        = string
  default     = "172.16.0.254"
}

variable "vm_cores" {
  description = "Number of vCPU cores"
  type        = number
  default     = 2
}

variable "vm_memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 8
}

variable "template_vm_id" {
  description = "Proxmox VM ID of the Packer-built template to clone"
  type        = number
  default     = 100
}

variable "storage_vm" {
  description = "Proxmox storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "storage_iso" {
  description = "Proxmox storage for cloud-init files (must be dir type)"
  type        = string
  default     = "local"
}
