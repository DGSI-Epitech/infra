packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL (e.g. https://192.168.100.2:8006/api2/json)"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox username (ex: root@pam)"
}

variable "proxmox_password" {
  type        = string
  sensitive   = true
  description = "Proxmox password"
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_storage_iso" {
  type        = string
  default     = "local"
  description = "Storage pool for the downloaded ISO"
}

variable "proxmox_storage_vm" {
  type        = string
  default     = "local-lvm"
  description = "Storage pool for the VM disk"
}

variable "template_vm_id" {
  type        = number
  default     = 100
  description = "Proxmox VM ID for the resulting template"
}

variable "build_username" {
  type    = string
  default = "ubuntu"
}

variable "build_password" {
  type      = string
  sensitive = true
  description = "Plain-text build password — used by Packer SSH communicator"
}

variable "build_password_encrypted" {
  type      = string
  sensitive = true
  description = "SHA-512 hashed password — generate with: echo 'password' | openssl passwd -6 -stdin"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
}

variable "iso_checksum" {
  type        = string
  description = "SHA256 checksum of the ISO — from https://releases.ubuntu.com/22.04/SHA256SUMS"
  default     = "9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
}

source "proxmox-iso" "ubuntu-2204" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id                = var.template_vm_id
  vm_name              = "ubuntu-22.04-template"
  template_description = "Ubuntu 22.04 LTS — built with Packer on ${formatdate("YYYY-MM-DD", timestamp())}"
  iso_url          = var.iso_url
  iso_checksum     = "sha256:${var.iso_checksum}"
  iso_storage_pool = var.proxmox_storage_iso
  unmount_iso      = true

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
    bridge = "vmbr0"
  }

  additional_iso_files {
    cd_content = {
      "/user-data" = templatefile("${path.root}/http/user-data.pkrtpl.hcl", {
        build_username           = var.build_username
        build_password_encrypted = var.build_password_encrypted
      })
      "/meta-data" = ""
    }
    cd_label         = "cidata"
    iso_storage_pool = var.proxmox_storage_iso
    device           = "ide3"
  }


  boot_wait = "5s"
  boot_command = [
    "<wait3>c<wait3>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/<enter><wait3>",
    "initrd /casper/initrd<enter><wait3>",
    "boot<enter>"
  ]

  communicator           = "ssh"
  ssh_username           = var.build_username
  ssh_password           = var.build_password
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 50

  qemu_agent = true
}

build {
  sources = ["source.proxmox-iso.ubuntu-2204"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "sudo apt-get install -y qemu-guest-agent curl wget git",
      "sudo systemctl enable qemu-guest-agent",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      # Reset cloud-init so the cloned VM gets a fresh first-boot
      "sudo cloud-init clean",
      "sudo rm -f /etc/machine-id",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/systemd/random-seed",
      "sync"
    ]
  }
}
