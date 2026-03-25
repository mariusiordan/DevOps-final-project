resource "aws_s3_bucket_lifecycle_configuration" "backups_retention" {
  bucket = "silverbank-tfstate-mariusiordan"

  rule {
    id     = "delete-old-db-backups"
    status = "Enabled"

    filter {
      prefix = "db-backups/"
    }

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = "silverbank-tfstate-mariusiordan"

  versioning_configuration {
    status = "Enabled"
  }
}