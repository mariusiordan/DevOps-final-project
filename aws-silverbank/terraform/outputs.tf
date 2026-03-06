output "jenkins_ip" {
  value = aws_instance.jenkins.public_ip
}

output "staging_ip" {
  value = aws_instance.staging.public_ip
}

output "prod_blue_ip" {
  value = aws_instance.prod_blue.public_ip
}

output "prod_green_ip" {
  value = aws_instance.prod_green.public_ip
}

output "nginx_ip" {
  value = aws_instance.nginx.public_ip
}