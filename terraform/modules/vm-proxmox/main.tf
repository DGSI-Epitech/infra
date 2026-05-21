# Création d'une VM de base depuis un template cloud-init
resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.name
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  # ------- Ressources CPU/RAM -------
  cpu {
    type  = "x86-64-v2-AES"
    cores = var.vm_cores
    numa  = false
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  # ------- Disque (clone du template) -------
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  # Redimensionner le disque si besoin
  disk {
    datastore_id = var.storage_vm
    size         = var.disk_size_gb
  }

  # ------- Réseau -------
  network_device {
    bridge   = var.network_bridge
    vlan_id  = var.network_tag != null ? var.network_tag : 0
    firewall = false
  }

  # ------- Cloud-Init -------
  initialization {
    user_account {
      keys     = [var.vm_ssh_public_key]
      username = "ubuntu"
    }

    ip_config {
      ipv4 {
        address = var.vm_ip_cidr
        gateway = var.vm_gateway
      }
    }

    # Hostname
    hostname = var.name

    # Custom user-data script (optionnel)
    user_data_base64 = var.cloud_init_script != null ? base64encode(var.cloud_init_script) : null
  }

  # ------- Tags pour organisation -------
  tags = var.tags

  # ------- Lifecycle -------
  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}
