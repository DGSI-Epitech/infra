terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "pfsense_vm" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  # --- Clonage du template ---
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  # --- Ressources ---
  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  # --- Interface WAN (Internet) ---
  network_device {
    bridge = var.wan_bridge
    model  = "virtio"
  }

  # --- Interface LAN (Réseau Local) ---
  network_device {
    bridge = var.lan_bridge
    model  = "virtio"
  }

  # On désactive l'agent QEMU car pfSense ne l'a pas par défaut
  agent {
    enabled = false
  }
}