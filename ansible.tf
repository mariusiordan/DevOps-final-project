locals {
  inventory = <<-EOT
  [edge]
  edge-nginx ansible_host=192.168.7.50 ansible_user=${var.ci_user}

  [prod]
  prod-vm1-BLUE ansible_host=192.168.7.101 ansible_user=${var.ci_user}
  prod-vm2-GREEN ansible_host=192.168.7.102 ansible_user=${var.ci_user}

  [db]
  db-postgresql ansible_host=192.168.7.60 ansible_user=${var.ci_user}

  [monitoring]
  stage-monitoring ansible_host=192.168.7.70 ansible_user=${var.ci_user}
  EOT
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = join("\n", [trimspace(local.inventory), ""])
}