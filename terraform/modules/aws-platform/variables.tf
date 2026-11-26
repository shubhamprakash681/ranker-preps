variable "name_prefix" {
  description = "Resource name prefix (nwo-<username>)."
  type        = string
}

variable "env" {
  description = "Environment name (dev or prod)."
  type        = string
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

variable "api_cpu" {
  description = "Fargate CPU units for API task (ceiling: 512)."
  type        = number
  default     = 256
}

variable "api_memory" {
  description = "Fargate memory MiB for API task (ceiling: 1024)."
  type        = number
  default     = 512
}

variable "api_min_capacity" {
  description = "Minimum API ECS tasks."
  type        = number
  default     = 2
}

variable "api_max_capacity" {
  description = "Maximum API ECS tasks (ceiling: 4)."
  type        = number
  default     = 4
}

variable "worker_cpu" {
  description = "Fargate CPU units for Worker task (ceiling: 256)."
  type        = number
  default     = 256
}

variable "worker_memory" {
  description = "Fargate memory MiB for Worker task (ceiling: 512)."
  type        = number
  default     = 512
}

variable "worker_min_capacity" {
  description = "Minimum Worker ECS tasks."
  type        = number
  default     = 1
}

variable "worker_max_capacity" {
  description = "Maximum Worker ECS tasks (ceiling: 2)."
  type        = number
  default     = 2
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days (ceiling: 30)."
  type        = number
  default     = 14
}

variable "skip_final_snapshot" {
  description = "Whether to skip RDS final snapshot on deletion."
  type        = bool
  default     = true
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window in days."
  type        = number
  default     = 0
}

variable "enable_edge_only" {
  description = "When true, ALB rejects direct requests without the CloudFront X-Origin-Verify header."
  type        = bool
  default     = false
}

variable "repo_url" {
  description = "Repository URL used to link paging alarms to runbooks."
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

variable "create_cloudwatch_dashboard" {
  description = "Whether to create aws_cloudwatch_dashboard (requires cloudwatch:PutDashboard on CI role)."
  type        = bool
  default     = false
}
