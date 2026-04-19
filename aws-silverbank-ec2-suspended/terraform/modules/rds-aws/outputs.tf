# ============================================================
# modules/rds-aws/outputs.tf
# ============================================================

output "rds_endpoint" {
  description = "RDS endpoint — used in app DATABASE_URL"
  value       = aws_db_instance.main.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.main.port
}

output "rds_db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "rds_instance_id" {
  description = "RDS instance identifier — used in monitoring"
  value       = aws_db_instance.main.identifier
}