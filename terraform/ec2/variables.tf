variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_name" {
  description = "Name of the EC2 instance"
  type        = string
}

variable "environment" {
  description = "Environment (dev, test, staging)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID (leave empty to use latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 20
}

variable "vpc_id" {
  description = "VPC ID (leave empty to lookup by vpc_name)"
  type        = string
  default     = ""
}

variable "vpc_name" {
  description = "Name of the VPC (used if vpc_id is empty)"
  type        = string
  default     = "dev"
}

variable "subnet_id" {
  description = "Subnet ID (leave empty to auto-select from VPC)"
  type        = string
  default     = ""
}

variable "security_group_rules" {
  description = "List of security group rules"
  type = list(object({
    port     = number
    protocol = string
    cidr     = string
  }))
  default = []
}

variable "owner" {
  description = "Owner of the resource"
  type        = string
}

variable "created_by" {
  description = "User who created the resource"
  type        = string
}

variable "created_at" {
  description = "Timestamp when resource was created"
  type        = string
}
