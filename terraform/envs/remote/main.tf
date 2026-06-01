module "pfsense" {
  source = "../../modules/pfsense"

  proxmox_node   = var.proxmox_node
  vm_id          = var.pfsense_vm_id
  template_vm_id = var.pfsense_cloud_template_id
  wan_bridge     = var.pfsense_wan_bridge
  # Ancien: lan_bridge = var.pfsense_lan_bridge (default "vmbr1") ← conflit avec pfSense OP
  lan_bridge     = var.pfsense_lan_bridge
  # DMZ/opt1 → même bridge que bastion (var.dmz_bridge = "vmbr3")
  dmz_bridge     = var.dmz_bridge
  vm_name        = "pfsense-cloud-01"
}

module "bastion" {
  source = "../../modules/bastion"

  proxmox_node      = var.proxmox_node
  vm_id             = var.bastion_vm_id
  template_vm_id    = var.template_ubuntu_vm_id
  vm_ssh_public_key = var.vm_ssh_public_key
  vm_ip_cidr        = var.bastion_ip_cidr
  vm_gateway        = var.dmz_gateway
  network_bridge    = var.dmz_bridge
  storage_vm        = var.storage_vm
  storage_iso       = var.storage_iso
}

module "website" {
  source = "../../modules/website"

  proxmox_node      = var.proxmox_node
  vm_id             = var.website_vm_id
  template_vm_id    = var.template_ubuntu_vm_id
  vm_ssh_public_key = var.vm_ssh_public_key
  vm_ip_cidr        = var.website_ip_cidr
  vm_gateway        = var.lan_gateway
  network_bridge    = var.lan_bridge
  storage_vm        = var.storage_vm
  storage_iso       = var.storage_iso

  depends_on = [module.bastion]
}

