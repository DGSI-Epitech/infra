provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    username    = "root"
    private_key = file(var.proxmox_ssh_private_key)

    node {
      name    = var.proxmox_node
      address = var.proxmox_node_address
    }
  }
}
