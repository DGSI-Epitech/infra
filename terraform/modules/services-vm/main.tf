resource "proxmox_download_file" "ubuntu_2204" {
  content_type = "iso"
  datastore_id = var.storage_iso
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  file_name    = "ubuntu-22.04-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_vm" "services_vm" {
  name      = "services-vm"
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  tags      = ["services", "ubuntu-22-04"]

  cpu {
    cores = var.vm_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = var.storage_vm
    file_id      = proxmox_download_file.ubuntu_2204.id
    interface    = "virtio0"
    discard      = "on"
    size         = var.disk_size_gb
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.vm_ip_cidr
        gateway = var.vm_gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.vm_ssh_public_key]
    }
  }
}
