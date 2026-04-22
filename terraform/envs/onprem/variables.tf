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

variable "template_vm_id" {
  description = "Proxmox VM ID for the Ubuntu template"
  type        = number
  default     = 9000
}

variable "storage_iso" {
  description = "Proxmox storage for cloud image download"
  type        = string
  default     = "local"
}

variable "storage_vm" {
  description = "Proxmox storage for VM disks"
  type        = string
  default     = "local-lvm"
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

variable "vault_vm_id" {
  description = "Proxmox VM ID for Vault"
  type        = number
  default     = 201
}

variable "vault_vm_ip_cidr" {
  description = "Vault VM IP address in CIDR notation"
  type        = string
  default     = "192.168.100.51/24"
}
