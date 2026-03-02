variable "proxmox_endpoint" {
  type        = string
  description = "Ex: https://192.168.7.12:8006"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Format: user@realm!token=SECRET"
}

variable "node_name" {
  type    = string
  default = "pve"
}

variable "template_vmid" {
  type    = number
  default = 9999
}

variable "vm_storage" {
  type        = string
  description = "Ex: zfs-nvmeT500-vm"
}

variable "bridge_lan" {
  type    = string
  default = "vmbr0"
}

variable "bridge_app" {
  type    = string
  default = "vmbr1"
}

variable "ci_user" {
  type    = string
  default = "devop"
}

variable "ci_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type = string
}

variable "lan_gateway" {
  type    = string
  default = "192.168.7.1"
}

variable "lan_prefix" {
  type    = number
  default = 24
}

variable "app_prefix" {
  type    = number
  default = 24
}
