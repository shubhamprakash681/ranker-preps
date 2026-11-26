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

variable "repo_url" {
  description = "Repository URL for runbook links in alarms."
  type        = string
  default     = "https://github.com/Deloitte-DT-Training"
}

variable "aws_backup_task_role_arn" {
  description = "Provided shared IAM role ARN for the scheduled backup ECS task."
  type        = string
}

variable "gcp_aws_wif_provider" {
  description = "Provided pre-built GCP Workload Identity provider path for AWS-to-GCP backup federation."
  type        = string
}

variable "gcp_backup_writer_sa" {
  description = "Provided shared GCP backup writer service account email."
  type        = string
}

variable "gcp_project_id" {
  description = "Shared GCP project ID used to compute the target GCS backup bucket name."
  type        = string
}
