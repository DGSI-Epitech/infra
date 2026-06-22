# 1. Recherche du sous-réseau dans NetBox
# Commenté : NetBox doit tourner avant ops-vm, or Vault (sur ops-vm) doit tourner avant NetBox.
# L'IP est maintenant passée en variable statique (var.vm_ip_address).
# data "netbox_prefix" "lan" {
#   prefix = "172.16.0.240/28"
# }

# 2. Réservation de la première IP libre liée à l'interface eth0 (déclarée plus bas)
# Commenté : remplacé par var.vm_ip_address (IP statique depuis config.env → VM_IP_OPS)
# resource "netbox_available_ip_address" "ops_vm_ip" {
#   prefix_id                    = data.netbox_prefix.lan.id
#   status                       = "active"
#   dns_name                     = "ops-vm.local"
#   description                  = "IP allouée dynamiquement par Terraform pour la VM Ops"
#   virtual_machine_interface_id = netbox_interface.ops_vm_eth0.id
# }

# 3. Création de la machine virtuelle dans Proxmox
resource "proxmox_virtual_environment_vm" "ops_vm" {
  name       = "ops-vm"
  node_name  = var.proxmox_node
  vm_id      = var.vm_id
  tags       = ["ops", "ubuntu-22-04"]
  boot_order = ["virtio0"]

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
    timeout = "60s"
  }

  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  disk {
    datastore_id = var.storage_vm
    interface    = "virtio0"
    size         = var.disk_size_gb
  }

  initialization {
    datastore_id = var.storage_iso

    ip_config {
      ipv4 {
        address = "${var.vm_ip_address},gw=${var.vm_gateway}"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.vm_ssh_public_key]
    }
  }
}

# 4. Enregistrement de la VM dans l'inventaire NetBox
# Commenté : NetBox n'existe pas encore au moment du déploiement ops-vm.
# À ré-activer après que services-vm soit déployé et NetBox opérationnel.
# resource "netbox_virtual_machine" "ops_vm_netbox" {
#   name       = "ops-vm"
#   cluster_id = 1
#   status     = "active"
#   vcpus      = var.vm_cores
#   memory_mb  = var.vm_memory_mb
# }

# 5. Création de l'interface réseau de la VM dans NetBox
# Commenté : dépend de netbox_virtual_machine.ops_vm_netbox (voir ci-dessus)
# resource "netbox_interface" "ops_vm_eth0" {
#   name               = "eth0"
#   virtual_machine_id = netbox_virtual_machine.ops_vm_netbox.id
# }

