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
