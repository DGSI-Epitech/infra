module "services_vm" {
  source = "../../modules/vm-proxmox"

  proxmox_node      = var.proxmox_node
  name              = "services-vm"
  vm_id             = var.services_vm_id
  template_vm_id    = var.template_ubuntu_vm_id
  vm_ssh_public_key = var.vm_ssh_public_key
  storage_iso       = var.storage_iso
  storage_vm        = var.storage_vm
  vm_cores          = 2
  vm_memory_mb      = 4096
  disk_size_gb      = 20
  network_bridge    = var.vm_network_bridge
  network_tag       = var.vm_network_vlan_tag
  tags              = ["services", "ubuntu-22.04"]
  depends_on        = [module.ops_vm] # attendre que Proxmox déverrouille le template
}

module "ops_vm" {
  source = "../../modules/vm-proxmox"

  proxmox_node      = var.proxmox_node
  name              = "ops-vm"
  vm_id             = var.ops_vm_id
  template_vm_id    = var.template_ubuntu_vm_id
  vm_ssh_public_key = var.vm_ssh_public_key
  storage_iso       = var.storage_iso
  storage_vm        = var.storage_vm
  vm_cores          = 4
  vm_memory_mb      = 8192
  disk_size_gb      = 30
  network_bridge    = var.vm_network_bridge
  network_tag       = var.vm_network_vlan_tag
  tags              = ["ops", "ubuntu-22.04"]
}

module "pfsense" {
  source = "../../modules/pfsense"

  proxmox_node   = var.proxmox_node
  vm_id          = var.pfsense_vm_id
  template_vm_id = var.pfsense_template_id
  lan_bridge     = "vmbr1"
  wan_bridge     = "vmbr2"
  lan_vlan_tag   = var.lan_vlan_tag
  wan_vlan_tag   = var.wan_vlan_tag
  vm_name        = "pfsense-fw-01"
}