# ============================================================
# OUTPUTS
# Used by Ansible to generate inventory
# ============================================================

output "edge_public_ip" {
  description = "Public IP of edge nginx - use this to access the app"
  value       = aws_instance.edge.public_ip
}

output "edge_public_dns" {
  description = "Public DNS of edge nginx"
  value       = aws_instance.edge.public_dns
}

output "blue_private_ip" {
  description = "Private IP of BLUE app server"
  value       = aws_instance.blue.private_ip
}

output "green_private_ip" {
  description = "Private IP of GREEN app server"
  value       = aws_instance.green.private_ip
}

output "db_private_ip" {
  description = "Private IP of PostgreSQL server"
  value       = aws_instance.db.private_ip
}

output "ami_id" {
  description = "Ubuntu 24.04 AMI used (for reference)"
  value       = data.aws_ami.ubuntu.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# Generates Ansible inventory automatically after terraform apply
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory-aws.ini"
  content  = <<-INI
    [edge]
    edge-nginx ansible_host=${aws_instance.edge.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519 ansible_ssh_common_args='-o StrictHostKeyChecking=no'

    [prod]
    prod-vm1-BLUE  ansible_host=${aws_instance.blue.private_ip}
    prod-vm2-GREEN ansible_host=${aws_instance.green.private_ip}

    [db]
    db-postgresql ansible_host=${aws_instance.db.private_ip}

    [prod:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyJump=ubuntu@${aws_instance.edge.public_ip}'

    [db:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyJump=ubuntu@${aws_instance.edge.public_ip}'
  INI
}
