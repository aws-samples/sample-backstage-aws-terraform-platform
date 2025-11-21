variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "environment" {
  description = "Environment (dev, test, staging, prod)"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable versioning for the bucket"
  type        = bool
  default     = false
}

variable "encryption_type" {
  description = "Encryption type (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (if using aws:kms)"
  type        = string
  default     = null
}

variable "block_public_access" {
  description = "Block all public access"
  type        = bool
  default     = true
}

variable "lifecycle_enabled" {
  description = "Enable lifecycle policy"
  type        = bool
  default     = false
}

variable "lifecycle_transition_days" {
  description = "Days before transitioning to IA storage"
  type        = number
  default     = 30
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

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
