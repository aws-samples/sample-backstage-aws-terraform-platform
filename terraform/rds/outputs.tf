output "db_instance_id" {
  description = "ID of the RDS instance"
  value       = module.rds.db_instance_identifier
}

output "db_instance_endpoint" {
  description = "Connection endpoint"
  value       = module.rds.db_instance_endpoint
}

output "db_instance_address" {
  description = "Address of the RDS instance"
  value       = module.rds.db_instance_address
}

output "db_instance_port" {
  description = "Port of the RDS instance"
  value       = module.rds.db_instance_port
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = module.rds.db_instance_arn
}

output "db_password_secret_arn" {
  description = "ARN of the AWS-managed Secrets Manager secret containing the master password"
  value       = module.rds.db_instance_master_user_secret_arn
  sensitive   = true
}

output "security_group_id" {
  description = "ID of the security group"
  value       = module.security_group.security_group_id
}
