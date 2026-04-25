packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url"        { type = string }
variable "proxmox_username"   { type = string }
variable "proxmox_password" {
  type      = string
  sensitive = true
}
variable "proxmox_node"       { type = string }
variable "proxmox_storage_vm" { type = string }
variable "template_vm_id"     { type = number }

variable "iso_url" {
  type    = string
  default = "https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:883fb7bc64fe548442ed007911341dd34e178449f8156ad65f7381a02b7cd9e4"
}

source "proxmox-iso" "pfsense" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true
  disable_kvm              = true  # Proxmox nested in VMware — no KVM available

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
    bridge = "vmbr0"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr1"
  }

  boot_iso {
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = "local"
    unmount          = true
  }

  communicator = "none"

  boot_key_interval = "100ms"
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
    "sed -i '' 's/em0/vtnet0/g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's/em1/vtnet1/g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's/192.168.1.1/172.16.255.254/g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's|<subnet>24</subnet>|<subnet>28</subnet>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's|<dnsserver/>|<dnsserver>1.1.1.1</dnsserver><dnsserver>8.8.8.8</dnsserver>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's|<ssh>|<ssh><enable>enabled</enable><port>22</port>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "/sbin/shutdown -p now<enter>"
  ]
}

build {
  sources = ["source.proxmox-iso.pfsense"]
}
