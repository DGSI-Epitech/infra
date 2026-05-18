variable "proxmox_endpoint" {
  description = "Proxmox API URL (e.g. https://172.21.87.155:8006)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox username (ex: root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
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

variable "template_ubuntu_vm_id" {
  description = "Proxmox VM ID for the Ubuntu template"
  type        = number
  default     = 100
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

variable "vm_ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}

variable "services_vm_id" {
  description = "Proxmox VM ID for Services"
  type        = number
}

variable "ops_vm_id" {
  description = "Proxmox VM ID for Ops VM (Vault + ELK)"
  type        = number
}

variable "pfsense_template_id" {
  description = "ID du template pfSense (Packer)"
  type        = number
}

variable "pfsense_vm_id" {
  description = "ID de la VM pfSense déployée"
  type        = number
}

variable "proxmox_ssh_private_key" {
  description = "Path to the SSH private key for Proxmox root SSH access (bpg provider disk import)"
  type        = string
}
