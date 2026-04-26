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

    bridge = "vmbr0" # WAN (Interface 1 : vtnet0)

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

  communicator = "none"

  boot_key_interval = "100ms"

  boot_wait         = "40s"

  boot_command = [

    "<enter><wait1s>",           # 1. Accept Copyright

    "<enter><wait1s>",           # 2. Install pfSense

    "<down><wait1s>",            # 3. Select Auto (UFS)

    "<enter><wait1s>",           # 4. Auto (UFS)

    "<enter><wait1s>",           # 5. Entire Disk

    "<enter><wait1s>",           # 6. MBR Partition Table

    "<enter><wait1s>",           # 7. Finish

    "<enter><wait25s>",          # 8. Commit

    "<right><wait2s><enter><wait5s>", # 9. Open Shell

    "mount /dev/vtbd0s1a /mnt<enter><wait2s>",

    #test

    # Patch Réseau (Interfaces LAN/WAN)

    "sed -i '' 's|em0|vtnet0|g' /mnt/cf/conf/config.xml<enter><wait2s>",

    "sed -i '' 's|em1|vtnet1|g' /mnt/cf/conf/config.xml<enter><wait2s>",

    # Set IP / Subnet (Délimiteur '|' utilisé pour ignorer les '/' des balises)

    "sed -i '' 's|<ipaddr>192.168.1.1</ipaddr>|<ipaddr>172.16.0.254</ipaddr>|g' /mnt/cf/conf/config.xml<enter><wait2s>",

    "sed -i '' 's|<subnet>28</subnet>|<subnet>24</subnet>|g' /mnt/cf/conf/config.xml<enter><wait2s>",

    # Disable DHCP & Correction propre du range

    "sed -i '' '/<dhcpd>/,/<.dhcpd>/ s|<enable/>||g' /mnt/cf/conf/config.xml<enter><wait2s>",

    "sed -i '' 's|<from>192.168.1.100</from>|<from>172.16.0.241</from>|g' /mnt/cf/conf/config.xml<enter><wait2s>",

    "sed -i '' 's|<to>192.168.1.199</to>|<to>172.16.0.253</to>|g' /mnt/cf/conf/config.xml<enter><wait2s>",

    # INJECTION GLOBALE SYSTÈME

    # Désactive le pare-feu + Bypass le wizard + Active le SSH + Configure les DNS

    "sed -i '' 's|<system>|<system><setupwizardcomplete/><enablesshd>yes</enablesshd><dnsserver>1.1.1.1</dnsserver><dnsserver>8.8.8.8</dnsserver>|g' /mnt/cf/conf/config.xml<enter><wait2s>",

    # Extinction propre pour finaliser le template

    "/sbin/shutdown -p now<enter>"

  ]

}

build {

  sources = ["source.proxmox-iso.pfsense"]

}