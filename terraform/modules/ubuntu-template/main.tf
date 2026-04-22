resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.storage_iso
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  file_name    = "ubuntu-22.04-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_vm" "template" {
  name      = "ubuntu-22.04-template"
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  template  = true
  started   = false

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = var.storage_vm
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    discard      = "on"
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}
