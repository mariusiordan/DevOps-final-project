# ============================================================
# ssm-transfer-bucket.tf
# Dedicated bucket for Ansible's aws_ssm connection plugin.
#
# The plugin stages files at <bucket>/<instance-id>/... - it does
# not honour a configurable prefix, so scoping access by prefix is
# not possible. A separate bucket keeps Terraform state and database
# backups out of reach of the CI role.
#
# Objects are transient (deleted after each task); a lifecycle rule
# clears anything left behind by interrupted runs.
# ============================================================

resource "aws_s3_bucket" "ssm_transfer" {
  bucket        = "silverbank-ssm-transfer-mariusiordan"
  force_destroy = true  # transient data only

  tags = { Name = "silverbank-ssm-transfer" }
}

resource "aws_s3_bucket_public_access_block" "ssm_transfer" {
  bucket                  = aws_s3_bucket.ssm_transfer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    id     = "expire-stale-transfers"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }
  }
}

output "ssm_transfer_bucket" {
  description = "Bucket used by the Ansible aws_ssm connection plugin"
  value       = aws_s3_bucket.ssm_transfer.id
}
