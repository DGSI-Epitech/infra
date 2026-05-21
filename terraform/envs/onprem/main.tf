# ============================================================================
# SITE ON-PREM - Infrastructure Proxmox
# ============================================================================
# 3 VMs:
# 1. pfSense - Firewall (pare-feu)
# 2. ELK Stack + Vault Hashicorp - Monitoring et secrets
# 3. Services VM - NetBox + Web Services
# ============================================================================

# ------- VM 1: pfSense Firewall -------
module "pfsense" {
  source = "../../modules/vm-proxmox"

  proxmox_node    = var.proxmox_node
  name            = "pfsense-fw-01"
  vm_id           = var.pfsense_vm_id
  template_vm_id  = var.pfsense_template_id
  storage_vm      = var.storage_vm
  vm_cores        = var.pfsense_cores
  vm_memory_mb    = var.pfsense_memory_mb
  disk_size_gb    = var.pfsense_disk_size_gb
  network_bridge  = var.vm_network_bridge
  network_tag     = var.vm_network_vlan_tag
  vm_ip_cidr      = var.pfsense_vm_ip_cidr
  vm_gateway      = var.pfsense_vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
  tags            = ["firewall", "pfsense", "security"]
}

# ------- VM 2: ELK Stack + Vault Hashicorp -------
module "elk_vault" {
  source = "../../modules/vm-proxmox"

  proxmox_node    = var.proxmox_node
  name            = "elk-vault-01"
  vm_id           = var.ops_vm_id
  template_vm_id  = var.template_ubuntu_vm_id
  storage_vm      = var.storage_vm
  vm_cores        = var.elk_cores
  vm_memory_mb    = var.elk_memory_mb
  disk_size_gb    = var.elk_disk_size_gb
  network_bridge  = var.vm_network_bridge
  network_tag     = var.vm_network_vlan_tag
  vm_ip_cidr      = var.elk_vm_ip_cidr
  vm_gateway      = var.elk_vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
  tags            = ["elk", "vault", "logging", "monitoring"]

  depends_on = [module.pfsense]
}

# ------- VM 3: Services VM (NetBox + Web) -------
module "services_vm" {
  source = "../../modules/vm-proxmox"

  proxmox_node    = var.proxmox_node
  name            = "services-vm-01"
  vm_id           = var.services_vm_id
  template_vm_id  = var.template_ubuntu_vm_id
  storage_vm      = var.storage_vm
  vm_cores        = var.services_cores
  vm_memory_mb    = var.services_memory_mb
  disk_size_gb    = var.services_disk_size_gb
  network_bridge  = var.vm_network_bridge
  network_tag     = var.vm_network_vlan_tag
  vm_ip_cidr      = var.services_vm_ip_cidr
  vm_gateway      = var.services_vm_gateway
  vm_ssh_public_key = var.vm_ssh_public_key
  tags            = ["services", "netbox", "web", "infrastructure"]

  depends_on = [module.elk_vault]
}