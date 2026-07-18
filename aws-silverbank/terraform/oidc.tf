# ============================================================
# oidc.tf
# GitHub Actions OIDC federation
#
# Replaces long-lived AWS access keys stored as GitHub secrets.
# GitHub issues a short-lived token per workflow run; AWS verifies
# it came from this repository and returns temporary credentials
# that expire automatically (~1 hour).
# ============================================================

# ------------------------------------------------------------
# IDENTITY PROVIDER
# Tells AWS to trust tokens issued by GitHub Actions.
# One provider per AWS account is enough - it is shared by all roles.
# ------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "github-actions-oidc" }
}

# ------------------------------------------------------------
# TRUST POLICY
# Defines WHO may assume the role:
#   - the token must come from the GitHub OIDC provider
#   - the audience must be sts.amazonaws.com
#   - the subject must match this repository, on main or staging
# Any other repo or branch is rejected by AWS before any code runs.
# ------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:mariusiordan/SilverBank-AWS:ref:refs/heads/main",
        "repo:mariusiordan/SilverBank-AWS:ref:refs/heads/staging",
        "repo:mariusiordan/SilverBank-AWS:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "silverbank-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  max_session_duration = 3600  # 1 hour

  tags = { Name = "silverbank-github-actions-role" }
}

# ------------------------------------------------------------
# PERMISSIONS
# Only what the pipelines actually need:
#   - describe instances (to build the SSM inventory)
#   - send commands and open sessions over SSM
#   - use the S3 transfer prefix required by the aws_ssm plugin
# No EC2 create/terminate, no IAM changes, no broad S3 access.
# ------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_permissions" {
  # Discover running instances by tag
  statement {
    sid       = "DescribeInstances"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # Run commands and open sessions on the managed instances
  statement {
    sid = "SsmExecution"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:DescribeInstanceInformation",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession",
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
    ]
    resources = ["*"]
  }

  # Dedicated transfer bucket for the Ansible aws_ssm plugin.
  # The plugin writes to <bucket>/<instance-id>/..., so access is
  # granted on the whole bucket - which holds only transient files.
  statement {
    sid = "SsmFileTransfer"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      "arn:aws:s3:::silverbank-ssm-transfer-mariusiordan",
      "arn:aws:s3:::silverbank-ssm-transfer-mariusiordan/*",
    ]
  }
}

resource "aws_iam_policy" "github_actions" {
  name   = "silverbank-github-actions-policy"
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

# ------------------------------------------------------------
# OUTPUT
# The ARN to put in the workflows as 'role-to-assume'
# ------------------------------------------------------------
output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC authentication"
  value       = aws_iam_role.github_actions.arn
}
