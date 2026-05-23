# --- Proxmox PVE2 ---

variable "proxmox_endpoint" {
  description = "Proxmox API URL for PVE2 (e.g. https://ns3183326.ip-146-59-253.eu:8006)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox root password"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name on PVE2"
  type        = string
  default     = "pve"
}

variable "proxmox_node_address" {
  description = "Proxmox PVE2 public IP for SSH (bpg provider disk import)"
  type        = string
}

variable "proxmox_ssh_private_key" {
  description = "Path to SSH private key for Proxmox root access"
  type        = string
}

# --- Templates ---

variable "pfsense_template_id" {
  description = "Proxmox VM ID du template pfSense sur PVE2"
  type        = number
}

variable "template_ubuntu_vm_id" {
  description = "Proxmox VM ID of the Ubuntu template on PVE2"
  type        = number
}

# --- SSH ---

variable "vm_ssh_public_key" {
  description = "SSH public key injected into VMs via cloud-init"
  type        = string
}

# --- VM IDs ---

variable "pfsense_vm_id" {
  description = "Proxmox VM ID pour pfSense S2"
  type        = number
}

variable "bastion_vm_id" {
  description = "Proxmox VM ID for the bastion (Teleport)"
  type        = number
}

variable "website_vm_id" {
  description = "Proxmox VM ID for the website"
  type        = number
}

# --- Réseau pfSense ---

variable "pfsense_wan_bridge" {
  description = "Bridge WAN pour pfSense S2"
  type        = string
  default     = "vmbr0"
}

variable "pfsense_lan_bridge" {
  description = "Bridge LAN Cloud pour pfSense S2"
  type        = string
  default     = "vmbr1"
}

# --- Réseau — valeurs fixes par design ---

variable "bastion_ip_cidr" {
  description = "Static IP for bastion in CIDR notation"
  type        = string
  default     = "10.255.255.249/29"
}

variable "website_ip_cidr" {
  description = "Static IP for website in CIDR notation"
  type        = string
  default     = "192.168.255.243/28"
}

variable "dmz_gateway" {
  description = "Gateway for DMZ network (pfSense S2 DMZ interface)"
  type        = string
  default     = "10.255.255.254"
}

variable "lan_gateway" {
  description = "Gateway for LAN Cloud network (pfSense S2 LAN interface)"
  type        = string
  default     = "192.168.255.254"
}

variable "dmz_bridge" {
  description = "Proxmox bridge for DMZ on PVE2"
  type        = string
  default     = "vmbr2"
}

variable "lan_bridge" {
  description = "Proxmox bridge for LAN Cloud on PVE2"
  type        = string
  default     = "vmbr1"
}

# --- Stockage ---

variable "storage_vm" {
  description = "Proxmox storage pool for VM disks on PVE2"
  type        = string
  default     = "local-lvm"
}

variable "storage_iso" {
  description = "Proxmox storage for cloud-init files on PVE2"
  type        = string
  default     = "local"
}
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
