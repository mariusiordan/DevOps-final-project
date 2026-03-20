terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "silverbank-tfstate-mariusiordan"
    key            = "aws-silverbank/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "silverbank-tf-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}