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
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "aws_alb_dns_name" {
  description = "AWS ALB DNS name."
  type        = string
  default     = "placeholder-alb.us-east-1.elb.amazonaws.com"
}

variable "gcp_api_url" {
  description = "GCP Cloud Run API URL."
  type        = string
  default     = "https://placeholder.a.run.app"
}

variable "origin_verify_secret" {
  description = "Shared secret for X-Origin-Verify header sent to AWS ALB."
  type        = string
  sensitive   = true
  default     = "placeholder-origin-verify"
}

variable "gcp_project_id" {
  description = "Shared GCP project ID."
  type        = string
}

variable "gcp_region" {
  description = "GCP region."
  type        = string
  default     = "us-east4"
}

variable "repo_url" {
  description = "Repository URL for runbook links."
  type        = string
  default     = "https://github.com/Deloitte-DT-Training"
}
