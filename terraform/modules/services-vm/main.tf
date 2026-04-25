resource "proxmox_virtual_environment_vm" "services_vm" {
  name      = "services-vm"
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  tags      = ["services", "ubuntu-22-04"]

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

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

  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.storage_iso
    ip_config {
      ipv4 {
        address = var.vm_ip_cidr
        gateway = var.vm_gateway
      }
    }

    user_account {
      username = "ubuntu"
      password = var.vm_password
      keys     = [var.vm_ssh_public_key]
    }
  }
}
