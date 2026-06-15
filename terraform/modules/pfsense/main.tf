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

  # --- Interface DMZ/opt1 (optionnelle — uniquement pfSense Cloud) ---
  # Ancien: pas d'interface DMZ → pfSense Cloud ne pouvait pas router vers bastion (vmbr3)
  dynamic "network_device" {
    for_each = var.dmz_bridge != "" ? [var.dmz_bridge] : []
    content {
      bridge = network_device.value
      model  = "virtio"
    }
  }

  # On désactive l'agent QEMU car pfSense ne l'a pas par défaut
  agent {
    enabled = false
  }
}