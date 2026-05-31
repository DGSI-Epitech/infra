variable "proxmox_endpoint" {
  description = "Proxmox API URL (ex: https://ns3183326.ip-146-59-253.eu:8006)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox username (ex: GR38@pve)"
  type        = string
  default     = "GR38@pve"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "vm002"
}

variable "proxmox_node_address" {
  description = "Proxmox node IP/hostname for SSH"
  type        = string
}

variable "proxmox_ssh_private_key" {
  description = "Path to the SSH private key for Proxmox root SSH access"
  type        = string
}
