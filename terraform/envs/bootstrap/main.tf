resource "proxmox_virtual_environment_role" "terraform" {
  role_id = "TerraformRole"

  privileges = [
    "Datastore.Audit",
    "Datastore.AllocateSpace",
    "Datastore.AllocateTemplate",
    "VM.Allocate",
    "VM.Audit",
    "VM.Clone",
    "VM.Config.CDROM",
    "VM.Config.CPU",
    "VM.Config.Cloudinit",
    "VM.Config.Disk",
    "VM.Config.HWType",
    "VM.Config.Memory",
    "VM.Config.Network",
    "VM.Config.Options",
    "VM.PowerMgmt",
    "SDN.Use",
    "Sys.Audit",
    "Sys.Modify",
  ]
}

resource "proxmox_user_token" "terraform" {
  user_id               = "root@pam"
  token_name            = var.terraform_token_name
  privileges_separation = true
  comment               = "Token Terraform — géré par IaC bootstrap"
}

resource "proxmox_virtual_environment_acl" "terraform" {
  token_id  = proxmox_user_token.terraform.id
  path      = "/"
  role_id   = proxmox_virtual_environment_role.terraform.role_id
  propagate = true
}

# vmbr0 — WAN (attaché à l'interface physique du nœud)
resource "proxmox_virtual_environment_network_linux_bridge" "vmbr0" {
  node_name = var.proxmox_node
  name      = "vmbr0"
  comment   = "WAN — bridge physique Internet"
}

# vmbr1 — LAN interne : Proxmox + VMs + pfSense LAN sur le même /24
resource "proxmox_virtual_environment_network_linux_bridge" "vmbr1" {
  node_name = var.proxmox_node
  name      = "vmbr1"
  address   = "172.16.0.1/24"
  comment   = "LAN — réseau interne 172.16.0.0/24"
}

# vmbr2 — Transit Proxmox→pfSense WAN (10.0.0.0/30)
resource "proxmox_virtual_environment_network_linux_bridge" "vmbr2" {
  node_name = var.proxmox_node
  name      = "vmbr2"
  address   = "10.0.0.1/30"
  comment   = "Transit Proxmox→pfSense WAN"
}
