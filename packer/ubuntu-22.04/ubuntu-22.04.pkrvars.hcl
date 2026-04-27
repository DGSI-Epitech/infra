proxmox_url         = "https://51.75.128.134:8006/api2/json"
proxmox_host="51.75.128.134"

proxmox_username    = "root@pam"
proxmox_password    = "OtJKS6kkUorgd2M1XpnQr7tZeLGF8W"
proxmox_password_encrypted = "$6$ppYAFTh619VDqxuG$eX7w1ubM5sGL2AR862gb3pUTc8oTzPZQImjNB330p6899Yr0Zd7CFgSIXhxN7PQYJ7gTO7y/V6CiHwIOer.Fk1"
proxmox_node        = "proxmox-site1"
proxmox_storage_iso = "local"
proxmox_storage_vm  = "local"
template_vm_id      = 100
build_username      = "ubuntu"
build_password_encrypted = "$6$LPZvwyatiXZDtuTk$t3SqXZ4TpDiLWEBHInYp0RHEnu8CaBYqiYIBZtehawidQYNrgx1WRmJeIEy3qmLiVag5j3nxK97wRyAtTD0n.0"
build_password      = "ubuntu"
iso_url             = "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
iso_checksum        = "<SHA256_FROM_RELEASES_PAGE>"

# Secrets — set via environment variables, never in this file:
# export PKR_VAR_proxmox_token='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
# export PKR_VAR_build_password='ubuntu'
# export PKR_VAR_build_password_encrypted=$(echo 'ubuntu' | openssl passwd -6 -stdin)
