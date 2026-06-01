variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
}

variable "template_vm_id" {
  description = "Proxmox VM ID of the Ubuntu template to clone"
  type        = number
}

variable "vm_ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}

variable "vm_ip_cidr" {
  description = "Static IP in CIDR notation (e.g. 10.255.255.249/29)"
  type        = string
}

variable "vm_gateway" {
  description = "Default gateway for the DMZ network"
  type        = string
}

variable "network_bridge" {
  description = "Proxmox bridge for DMZ network"
  type        = string
  default     = "vmbr2"
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
  default     = 20
}

variable "storage_vm" {
  description = "Proxmox storage pool for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "storage_iso" {
  description = "Proxmox storage for cloud-init files"
  type        = string
  default     = "local"
}
