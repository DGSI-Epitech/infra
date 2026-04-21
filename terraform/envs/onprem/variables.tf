variable "proxmox_endpoint" {
  description = "Proxmox API URL (e.g. https://192.168.100.2:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token — format: user@realm!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "proxmox_node_address" {
  description = "Proxmox node IP address for SSH (e.g. 172.16.231.129)"
  type        = string
}

variable "proxmox_ssh_private_key" {
  description = "Path to the SSH private key for Proxmox root access"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "vm_ip_cidr" {
  description = "Services VM IP address in CIDR notation"
  type        = string
  default     = "192.168.100.50/24"
}

variable "vm_gateway" {
  description = "Default gateway for the services VM"
  type        = string
  default     = "192.168.100.1"
}

variable "vm_ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}
