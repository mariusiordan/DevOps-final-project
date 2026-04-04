# ============================================================
# modules/ecr-aws/outputs.tf
# ============================================================

output "frontend_repository_url" {
  description = "ECR frontend repository URL"
  value       = aws_ecr_repository.frontend.repository_url
}

output "backend_repository_url" {
  description = "ECR backend repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_repository_arn" {
  description = "ECR frontend repository ARN"
  value       = aws_ecr_repository.frontend.arn
}

output "backend_repository_arn" {
  description = "ECR backend repository ARN"
  value       = aws_ecr_repository.backend.arn
}

output "registry_id" {
  description = "ECR registry ID"
  value       = aws_ecr_repository.frontend.registry_id
}