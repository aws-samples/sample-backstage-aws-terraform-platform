terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration will be provided via backend.config file
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = var.environment
      Owner       = var.owner
      CreatedBy   = var.created_by
      CreatedAt   = var.created_at
    }
  }
}

data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
}

data "aws_subnets" "private" {
  count = length(var.subnet_ids) == 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  # Try to find private subnets by common naming patterns
  filter {
    name   = "tag:Name"
    values = ["*private*", "*Private*", "*PRIVATE*"]
  }
}

# Fallback: get all subnets if no private subnets found
data "aws_subnets" "all" {
  count = length(var.subnet_ids) == 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  # Use private subnets if found, otherwise use all subnets
  # RDS needs at least 2 subnets in different AZs
  available_subnets = length(data.aws_subnets.private[0].ids) > 0 ? data.aws_subnets.private[0].ids : data.aws_subnets.all[0].ids

  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : local.available_subnets
}

locals {
  engine_map = {
    "postgres" = "postgres"
    "mysql"    = "mysql"
    "mariadb"  = "mariadb"
  }

  engine_version_map = {
    "postgres-14"  = "14.10"
    "postgres-15"  = "15.5"
    "mysql-8.0"    = "8.0.35"
    "mariadb-10.6" = "10.6.16"
  }
}

# AWS RDS will manage the master password in Secrets Manager automatically
# This eliminates the need for manual password generation and rotation
# The password will be stored in Secrets Manager with automatic KMS encryption

# Security group for RDS
module "security_group" {
  # terraform-aws-security-group v5.2.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=eb9fb97125c6fd9556287193150a628cdddf5c4d"

  name        = "${var.db_identifier}-sg"
  description = "Security group for RDS instance ${var.db_identifier}"
  vpc_id      = local.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = "10.0.0.0/8"
      description = "Allow database access from VPC"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  ]

  tags = {
    Name = "${var.db_identifier}-sg"
  }
}

# RDS instance using official AWS module
module "rds" {
  # terraform-aws-rds v6.10.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-rds.git?ref=4481ddde97e5408a0f0a91e00472f1ef024223d3"

  identifier = var.db_identifier

  engine               = local.engine_map[var.engine]
  engine_version       = local.engine_version_map[var.engine_version]
  family               = "${local.engine_map[var.engine]}${split(".", local.engine_version_map[var.engine_version])[0]}"
  major_engine_version = split(".", local.engine_version_map[var.engine_version])[0]
  instance_class       = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = var.storage_encrypted

  db_name  = var.db_name
  username = var.master_username
  port     = var.port

  # AWS-managed master password in Secrets Manager
  # This automatically creates a secret with KMS encryption and enables rotation
  manage_master_user_password = true
  master_user_secret_kms_key_id = var.kms_key_id != "" ? var.kms_key_id : null

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [module.security_group.security_group_id]
  publicly_accessible    = var.publicly_accessible

  # High availability
  multi_az = var.multi_az

  # Backup
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Monitoring
  enabled_cloudwatch_logs_exports = var.engine == "postgres" ? ["postgresql"] : var.engine == "mysql" ? ["error", "general", "slowquery"] : ["error", "general", "slowquery"]

  # Upgrades and deletion
  auto_minor_version_upgrade       = var.auto_minor_version_upgrade
  deletion_protection              = var.deletion_protection
  skip_final_snapshot              = !var.deletion_protection
  final_snapshot_identifier_prefix = var.deletion_protection ? "${var.db_identifier}-final" : null

  tags = {
    Name = var.db_identifier
  }
}

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.db_identifier}-"
  subnet_ids  = local.subnet_ids

  tags = {
    Name = "${var.db_identifier}-subnet-group"
  }
}
