output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.ec2_instance.id
}

output "instance_public_ip" {
  description = "Public IP of the instance"
  value       = module.ec2_instance.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the instance"
  value       = module.ec2_instance.private_ip
}

output "instance_public_dns" {
  description = "Public DNS of the instance"
  value       = module.ec2_instance.public_dns
}

output "security_group_id" {
  description = "ID of the security group"
  value       = module.security_group.security_group_id
}

output "iam_role_name" {
  description = "Name of the IAM role"
  value       = module.ec2_iam_role.iam_role_name
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = module.ec2_iam_role.iam_role_arn
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = module.ec2_iam_role.iam_instance_profile_name
}
