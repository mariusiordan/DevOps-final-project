variable "aws_region" {
  default = "eu-north-1"
}

variable "instance_type" {
  default = "t3.micro"  # t2.micro nu e disponibil în Stockholm
}

variable "key_name" {
  description = "Numele cheii SSH din AWS"
}

variable "my_ip" {
  description = "IP-ul tău pentru acces SSH (ex: 1.2.3.4/32)"
}