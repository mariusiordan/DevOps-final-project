terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.97.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

locals {
  vms = {
    edge = {
      name    = "edge-nginx"
      vmid    = 850
      cores   = 2
      ram_mb  = 2048
      disk_gb = 32
      lan_ip  = "192.168.7.50"
      app_ip  = "10.10.20.10"
    }
    blue = {
      name    = "prod-vm1-BLUE"
      vmid    = 810
      cores   = 2
      ram_mb  = 4096
      disk_gb = 32
      lan_ip  = "192.168.7.101"
      app_ip  = "10.10.20.11"
    }
    green = {
      name    = "prod-vm2-GREEN"
      vmid    = 811
      cores   = 2
      ram_mb  = 4096
      disk_gb = 32
      lan_ip  = "192.168.7.102"
      app_ip  = "10.10.20.12"
    }
    db = {
      name    = "db-postgresql"
      vmid    = 860
      cores   = 2
      ram_mb  = 4096
      disk_gb = 32
      lan_ip  = "192.168.7.60"
      app_ip  = "10.10.20.20"
    }
    stage = {
      name    = "monitoring-staging"
      vmid    = 800
      cores   = 2
      ram_mb  = 4096
      disk_gb = 32
      lan_ip  = "192.168.7.70"
      app_ip  = "10.10.20.30"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  name      = each.value.name
  node_name = var.node_name
  vm_id     = each.value.vmid

  started = true
  on_boot = true

  # Clone from template VMID=9999
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.ram_mb
  }

  # Primary disk
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
    cache        = "none"
  }

  boot_order = [ "scsi0" ]
  # net0 -> vmbr0 (LAN/Internet)
  network_device {
    bridge = var.bridge_lan
    model  = "virtio"
  }

  # net1 -> vmbr1 (internal APP)
  network_device {
    bridge = var.bridge_app
    model  = "virtio"
  }

  initialization {
    user_account {
      username = var.ci_user
      password = var.ci_password
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = ["1.1.1.1"]
    }

    # net0 config (vmbr0) - with gateway
    ip_config {
      ipv4 {
        address = "${each.value.lan_ip}/${var.lan_prefix}"
        gateway = var.lan_gateway
      }
    }

    # net1 config (vmbr1) - no gateway
    ip_config {
      ipv4 {
        address = "${each.value.app_ip}/${var.app_prefix}"
      }
    }
  }

  agent {
    enabled = true
  }
}
