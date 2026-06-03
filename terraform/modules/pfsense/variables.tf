variable "proxmox_node" { type = string }
variable "vm_id" { type = number }
variable "template_vm_id" { type = number }
variable "vm_name" { type = string }
variable "wan_bridge" { type = string }
variable "lan_bridge" { type = string }
# Interface DMZ/opt1 optionnelle — vide = pas d'interface (pfSense OP), non vide = 3ème carte (pfSense Cloud)
variable "dmz_bridge" {
  type    = string
  default = ""
}