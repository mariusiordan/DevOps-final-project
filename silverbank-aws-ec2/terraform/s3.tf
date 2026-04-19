# ============================================================
# s3.tf
# S3 bucket configuration for tfstate and DB backups
# We don't create the bucket here - it already exists
# We only manage its configuration
# ============================================================

# ============================================================
# VERSIONING
# ============================================================

# Keeps every version of the tfstate file
# If terraform apply breaks something, you can restore a previous state
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = "silverbank-tfstate-mariusiordan"

  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================
# LIFECYCLE RULES
# ============================================================

# Automatically deletes DB backups older than 30 days
# Without this rule, backups accumulate forever and cost money
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