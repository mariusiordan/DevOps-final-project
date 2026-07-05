# ============================================================
# iam.tf
# IAM role for the db VM to access S3 (database backups)
# No access keys stored anywhere - AWS provides temporary
# credentials automatically to the EC2 instance
# ============================================================

# ------------------------------------------------------------
# TRUST POLICY
# Says: "the EC2 service is allowed to assume this role"
# Without this, nothing could use the role
# ------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ------------------------------------------------------------
# THE ROLE
# An identity the db VM can take on
# ------------------------------------------------------------
resource "aws_iam_role" "db_backup" {
  name               = "silverbank-db-backup-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "silverbank-db-backup-role" }
}

# ------------------------------------------------------------
# PERMISSIONS POLICY
# What the role is allowed to do:
# read/write/list objects under db-backups/ in the tfstate bucket
# Nothing else - least privilege
# ------------------------------------------------------------
data "aws_iam_policy_document" "db_backup_s3" {
  # Allow put/get/delete objects, but ONLY in the db-backups/ folder
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::silverbank-tfstate-mariusiordan/db-backups/*"
    ]
  }

  # Allow listing the bucket, but only the db-backups/ prefix
  # Needed so restore can find the latest backup
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::silverbank-tfstate-mariusiordan"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["db-backups/*"]
    }
  }
}

# Attach the permissions policy to the role
resource "aws_iam_role_policy" "db_backup_s3" {
  name   = "silverbank-db-backup-s3-policy"
  role   = aws_iam_role.db_backup.id
  policy = data.aws_iam_policy_document.db_backup_s3.json
}

# ------------------------------------------------------------
# INSTANCE PROFILE
# The wrapper that lets an EC2 instance use the role
# EC2 instances attach a "profile", not a "role" directly
# ------------------------------------------------------------
resource "aws_iam_instance_profile" "db_backup" {
  name = "silverbank-db-backup-profile"
  role = aws_iam_role.db_backup.name
}