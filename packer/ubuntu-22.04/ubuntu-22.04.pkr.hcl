packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# --- VARIABLES ---
variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_username" {
  type        = string
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_storage_iso" {
  type    = string
  default = "local"
}

variable "proxmox_storage_vm" {
  type    = string
  default = "local-lvm"
}

variable "template_vm_id" {
  type    = number
  default = 100
}

variable "build_username" {
  type    = string
  default = "ubuntu"
}

variable "build_password" {
  type      = string
  sensitive = true
}

variable "build_password_encrypted" {
  type      = string
  sensitive = true
}

variable "proxmox_host" {
  type        = string
  description = "IP réelle de Proxmox pour le bastion SSH"
}

# --- SOURCE ---
source "proxmox-iso" "ubuntu-2204" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id                = var.template_vm_id
  vm_name              = "ubuntu-22.04-template"
  template_description = "Ubuntu 22.04 LTS — built with Packer on ${formatdate("YYYY-MM-DD", timestamp())}"

  # Correction des warnings ISO
  iso_storage_pool = var.proxmox_storage_iso
  boot_iso {
    iso_file = "local:iso/c968bbbeb22702b3f10a07276c8ca06720e80c4c.iso"
    unmount  = true
  }

  cpu_type = "x86-64-v2-AES"
  cores    = 2
  memory   = 2048

  disks {
    type         = "virtio"
    disk_size    = "20G"
    storage_pool = var.proxmox_storage_vm
    discard      = true
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr1"
  }

  # Correction du warning additional_iso_files
  additional_iso_files {
    cd_label         = "cidata"
    cd_content = {
      "/user-data" = templatefile("${path.root}/http/user-data.pkrtpl.hcl", {
        build_username           = var.build_username
        build_password_encrypted = var.build_password_encrypted
        build_password           = var.build_password
      })
      "/meta-data" = ""
    }
    iso_storage_pool = var.proxmox_storage_iso
    type             = "ide"
    index            = 3
  }

  boot_wait = "10s"
  boot_command = [
    "c<wait3>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud<enter><wait5>",
    "initrd /casper/initrd<enter><wait3>",
    "boot<enter>"
  ]

  # Configuration SSH
  communicator              = "ssh"
  ssh_host                  = "172.16.0.100"
  ssh_username              = var.build_username
  ssh_password              = var.build_password
  ssh_timeout               = "45m" # Augmenté pour plus de sécurité
  pause_before_connecting   = "2m"
  ssh_handshake_attempts    = 100

  # Bastion pour passer par l'IP publique de Proxmox
  ssh_bastion_host     = var.proxmox_host
  ssh_bastion_username = "root"
  ssh_bastion_password = var.proxmox_password

  qemu_agent = true
}

# --- BUILD ---
build {
  sources = ["source.proxmox-iso.ubuntu-2204"]

  # BLOC 1 : Mise à jour et Reboot
  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "echo 'Attente de cloud-init...'",
      "sudo cloud-init status --wait",

      "echo 'Nettoyage forcé des verrous APT...'",
      "sudo fuser -kk /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock || true",

      "echo 'Mise à jour du système...'",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",

      "echo 'Redémarrage pour stabiliser le système...'",
      "sudo reboot"
    ]
  }

  # BLOC 2 : Installation finale et Nettoyage (s'exécute après le reboot)
  provisioner "shell" {
    pause_before = "20s"
    inline = [
      "echo 'Installation des outils additionnels...'",
      "sudo apt-get install -y qemu-guest-agent curl wget git",
      "sudo systemctl enable qemu-guest-agent",

      "echo 'Nettoyage final du template...'",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo cloud-init clean",
      "sudo rm -f /etc/machine-id",
      "sudo touch /etc/machine-id",
      "sync"
    ]
  }
}