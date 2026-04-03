# ============================================================
# modules/ecr-aws/outputs.tf
# ============================================================

output "repository_url" {
  description = "ECR repository URL — used in GitHub Actions to push images"
  value       = aws_ecr_repository.main.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN — used in IAM policies"
  value       = aws_ecr_repository.main.arn
}

output "registry_id" {
  description = "ECR registry ID (AWS account ID)"
  value       = aws_ecr_repository.main.registry_id
}