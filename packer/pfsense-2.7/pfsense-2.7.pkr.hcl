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
variable "proxmox_token" { 
  type      = string
  sensitive = true 
}
variable "proxmox_node" { type = string }
variable "proxmox_storage_vm" { type = string }
variable "template_vm_id" { type = number }

# --- Source ---
source "proxmox-iso" "pfsense" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true
  http_directory = "http"

  vm_id                = var.template_vm_id
  vm_name              = "pfsense-2.7.2-template"
  template_description = "pfSense 2.7.2 Template — Built via Packer"
  
  unmount_iso = true
  
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

  iso_file = "local:iso/pfSense-CE-2.7.2-RELEASE-amd64.iso"
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
    # Patch Réseau (Interfaces & IP)
    "sed -i '' 's/em0/vtnet0/g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's/em1/vtnet1/g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's/192.168.1.1/172.16.255.254/g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's|<subnet>24</subnet>|<subnet>28</subnet>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    
    # Patch Services (DNS, SSH, Bogons)
    "sed -i '' 's|<dnsserver/>|<dnsserver>1.1.1.1</dnsserver><dnsserver>8.8.8.8</dnsserver>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's|<dnsforwarder>|<dnsforwarder><enable>yes</enable><cache_hosts>yes</cache_hosts>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's|<blockprivaddr/>|<blockprivaddr/><blockbogons/>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    "sed -i '' 's|<ssh>|<ssh><enable>enabled</enable><port>22</port>|g' /mnt/cf/conf/config.xml<enter><wait2s>",
    
    "/sbin/shutdown -p now<enter>"
  ]
}

build {
  sources = ["source.proxmox-iso.pfsense"]
}