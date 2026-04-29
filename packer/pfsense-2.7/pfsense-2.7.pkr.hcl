packer {

  required_plugins {

    proxmox = {

      version = ">= 1.1.8"

      source  = "github.com/hashicorp/proxmox"

    }

  }

}

# --- Variables ---

variable "proxmox_url" { type = string }

variable "proxmox_username" { type = string }

variable "proxmox_password" {

  type      = string

  sensitive = true

}

variable "proxmox_node" { type = string }

variable "proxmox_storage_vm" { type = string }

variable "template_vm_id" { type = number }

variable "pfsense_admin_ssh_public_key" {
  type        = string
  description = "SSH public key to inject into pfSense admin account (base64-encoded in config.xml)"
}

variable "iso_url" {
  type    = string
  default = "https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:883fb7bc64fe548442ed007911341dd34e178449f8156ad65f7381a02b7cd9e4"
}

# --- Source ---

source "proxmox-iso" "pfsense" {

  proxmox_url              = var.proxmox_url

  username                 = var.proxmox_username

  password                 = var.proxmox_password

  node                     = var.proxmox_node

  insecure_skip_tls_verify = true

  vm_id                = var.template_vm_id

  vm_name              = "pfsense-2.7.2-template"

  template_description = "pfSense 2.7.2 Template — Built via Packer"

  os       = "l26"

  cpu_type = "x86-64-v2-AES"

  cores    = 2

  memory   = 2048

  disks {

    type         = "virtio"

    disk_size    = "10G"

    storage_pool = var.proxmox_storage_vm

  }

  network_adapters {

    model  = "virtio"

    bridge = "vmbr2" # WAN (Interface 1 : vtnet0)

  }

  network_adapters {

    model  = "virtio"

    bridge = "vmbr1" # LAN (Interface 2 : vtnet1)

  }

  boot_iso {
    #iso_url          = var.iso_url
    #iso_checksum     = var.iso_checksum
    iso_file = "local:iso/24a35fbd9011bd358bc49b633aacc5c2af375386.iso"
    iso_storage_pool = "local"
    unmount          = true
  }
additional_iso_files {
    cd_content = {
      "/config.xml" = templatefile("${path.root}/http/config.xml.pkrtpl.hcl", {
        admin_authorized_keys_b64 = base64encode(var.pfsense_admin_ssh_public_key)
      })
    }
    cd_label         = "PFSENSE_CFG"
    iso_storage_pool = "local"
    device           = "ide3"

  }


  communicator      = "none"
  boot_key_interval = "200ms"
  boot_wait         = "40s"

  boot_command = [
    "<enter><wait1s>",
    "<enter><wait1s>",
    "<down><wait1s>",
    "<enter><wait1s>",
    "<enter><wait1s>",
    "<enter><wait1s>",
    "<enter><wait1s>",
    "<enter><wait25s>",
    "<right><wait2s><enter><wait5s>",

    "mount /dev/vtbd0s1a /mnt<enter><wait2s>",
    "mkdir -p /mnt/cdrom<enter><wait1s>",
    "mount -t cd9660 /dev/cd1 /mnt/cdrom<enter><wait2s>",
    "cp /mnt/cdrom/config.xml /mnt/cf/conf/config.xml<enter><wait2s>",
    "sync && sync<enter><wait2s>",
    "/sbin/shutdown -p now<enter>"
  ]

}

build {

  sources = ["source.proxmox-iso.pfsense"]

}