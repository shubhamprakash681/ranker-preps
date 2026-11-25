variable "username" {
  description = "Lowercase Deloitte username used for resource naming and mandatory username tag."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix (nwo-<username>)."
  type        = string
}

variable "env" {
  description = "Environment name (dev or prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "image_digest" {
  description = "Immutable sha256 digest of the container image pushed to ECR."
  type        = string
  default     = ""
}
