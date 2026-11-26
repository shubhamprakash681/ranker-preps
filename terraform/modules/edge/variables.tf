variable "name_prefix" {
  description = "Resource name prefix (nwo-<username>)."
  type        = string
}

variable "env" {
  description = "Environment name (dev or prod)."
  type        = string
}

variable "aws_alb_dns_name" {
  description = "AWS ALB DNS name."
  type        = string
}

variable "gcp_api_host" {
  description = "GCP Cloud Run API hostname (without https://)."
  type        = string
}

variable "origin_verify_secret" {
  description = "Shared secret sent as X-Origin-Verify header to AWS ALB."
  type        = string
  sensitive   = true
}

variable "username" {
  description = "Lowercase Deloitte username for GCP monitoring user_labels."
  type        = string
}

variable "gcp_project_id" {
  description = "Shared GCP project ID for synthetic uptime check."
  type        = string
}

variable "repo_url" {
  description = "Repository URL for runbook links."
  type        = string
  default     = "https://github.com/Deloitte-DT-Training"
}
