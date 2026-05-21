variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "name" {
  description = "VM name"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
}

variable "template_vm_id" {
  description = "Proxmox template VM ID to clone from"
  type        = number
}

# ------- CPU/RAM -------
variable "vm_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "vm_memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

# ------- Disque -------
variable "disk_size_gb" {
  description = "Root disk size in GB"
  type        = number
  default     = 20
}

variable "storage_vm" {
  description = "Proxmox storage for VM disks"
  type        = string
}

# ------- Réseau -------
variable "network_bridge" {
  description = "Virtual bridge for network interface (e.g., vmbr0)"
  type        = string
}

variable "network_tag" {
  description = "VLAN tag (0 for no tag, null for untagged)"
  type        = number
  default     = null
}

variable "vm_ip_cidr" {
  description = "VM IP address in CIDR format (e.g., 192.168.100.50/24)"
  type        = string
}

variable "vm_gateway" {
  description = "Default gateway IP"
  type        = string
}

# ------- Cloud-Init -------
variable "vm_ssh_public_key" {
  description = "SSH public key for cloud-init user account"
  type        = string
}

variable "cloud_init_script" {
  description = "Custom cloud-init user-data script"
  type        = string
  default     = null
}

# ------- Tags -------
variable "tags" {
  description = "Tags for VM organization"
  type        = list(string)
  default     = []
}
