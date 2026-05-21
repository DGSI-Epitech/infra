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

# ------- Network Configuration -------
variable "vm_network_bridge" {
  description = "Virtual bridge for Ubuntu VMs (e.g., vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "vm_network_vlan_tag" {
  description = "VLAN tag for Ubuntu VMs (0 for no tag)"
  type        = number
  default     = 0
}

# ------- VM IPs -------
variable "pfsense_vm_ip_cidr" {
  description = "pfSense VM IP in CIDR format"
  type        = string
}

variable "pfsense_vm_gateway" {
  description = "pfSense VM gateway"
  type        = string
}

variable "elk_vm_ip_cidr" {
  description = "ELK Stack VM IP in CIDR format"
  type        = string
}

variable "elk_vm_gateway" {
  description = "ELK Stack VM gateway"
  type        = string
}

variable "services_vm_ip_cidr" {
  description = "Services VM (NetBox + Web) IP in CIDR format"
  type        = string
}

variable "services_vm_gateway" {
  description = "Services VM gateway"
  type        = string
}

# ------- VM Specs -------
variable "pfsense_cores" {
  description = "pfSense CPU cores"
  type        = number
  default     = 2
}

variable "pfsense_memory_mb" {
  description = "pfSense RAM in MB"
  type        = number
  default     = 2048
}

variable "pfsense_disk_size_gb" {
  description = "pfSense disk size in GB"
  type        = number
  default     = 20
}

variable "elk_cores" {
  description = "ELK Stack CPU cores"
  type        = number
  default     = 4
}

variable "elk_memory_mb" {
  description = "ELK Stack RAM in MB"
  type        = number
  default     = 8192
}

variable "elk_disk_size_gb" {
  description = "ELK Stack disk size in GB"
  type        = number
  default     = 50
}

variable "services_cores" {
  description = "Services (NetBox + Web) CPU cores"
  type        = number
  default     = 4
}

variable "services_memory_mb" {
  description = "Services RAM in MB"
  type        = number
  default     = 8192
}

variable "services_disk_size_gb" {
  description = "Services disk size in GB"
  type        = number
  default     = 50
}
