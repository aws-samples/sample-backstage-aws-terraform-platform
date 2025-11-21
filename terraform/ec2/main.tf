terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

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

# Data sources
data "aws_vpc" "this" {
  count = var.vpc_id == "" ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_vpc" "by_id" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.this[0].id
}

data "aws_subnets" "private" {
  count = var.subnet_id == "" ? 1 : 0

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
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  # Use private subnets if found, otherwise use any subnet
  available_subnets = length(data.aws_subnets.private[0].ids) > 0 ? data.aws_subnets.private[0].ids : data.aws_subnets.all[0].ids

  subnet_id = var.subnet_id != "" ? var.subnet_id : local.available_subnets[0]
}

# IAM role for EC2 instance using official AWS module
# Only attaches AmazonSSMManagedInstanceCore policy for secure access via Systems Manager
module "ec2_iam_role" {
  # terraform-aws-iam v5.44.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-assumable-role?ref=89fe17a6549728f1dc7e7a8f7b707486dfb45d89"

  create_role = true
  role_name   = "${var.instance_name}-role"

  trusted_role_services = ["ec2.amazonaws.com"]

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  create_instance_profile = true

  tags = {
    Name = "${var.instance_name}-role"
  }
}

# Security group
module "security_group" {
  # terraform-aws-security-group v5.2.0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=eb9fb97125c6fd9556287193150a628cdddf5c4d"

  name        = "${var.instance_name}-sg"
  description = "Security group for ${var.instance_name}"
  vpc_id      = local.vpc_id

  ingress_with_cidr_blocks = [
    for rule in var.security_group_rules : {
      from_port   = rule.port
      to_port     = rule.port
      protocol    = rule.protocol
      cidr_blocks = rule.cidr
      description = "Allow ${rule.protocol}/${rule.port}"
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
    Name = "${var.instance_name}-sg"
  }
}

# EC2 instance
module "ec2_instance" {
  # terraform-aws-ec2-instance v5.7.1
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ec2-instance.git?ref=28b2c723dc5168d48b2a31214b2c26e88094c5fa"

  name = var.instance_name

  ami                         = var.ami_id != "" ? var.ami_id : null
  ami_ssm_parameter           = var.ami_id == "" ? "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" : null
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [module.security_group.security_group_id]
  associate_public_ip_address = false
  iam_instance_profile        = module.ec2_iam_role.iam_instance_profile_name
  monitoring                  = true # Enable detailed monitoring for better observability

  root_block_device = [{
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }]

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = var.instance_name
  }
}
