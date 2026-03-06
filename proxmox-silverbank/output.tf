output "vm_info" {
  value = {
    for k, v in local.vms : k => {
      name   = v.name
      lan_ip = v.lan_ip
      app_ip = v.app_ip
    }
  }
}