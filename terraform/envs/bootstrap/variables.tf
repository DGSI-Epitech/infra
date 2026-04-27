variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_node_address" {
  type = string
}

variable "proxmox_ssh_private_key" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

variable "terraform_token_name" {
  description = "Nom du token API Proxmox pour Terraform"
  type        = string
  default     = "terraform"
}
