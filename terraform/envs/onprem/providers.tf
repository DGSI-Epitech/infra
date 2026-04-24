provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  username  = var.proxmox_username
  password  = var.proxmox_password
  insecure  = true

  ssh {
    username    = "root"
    private_key = file(pathexpand(var.proxmox_ssh_private_key))

    node {
      name    = var.proxmox_node
      address = var.proxmox_node_address
    }
  }
}
