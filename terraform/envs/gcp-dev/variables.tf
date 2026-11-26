variable "username" {
  description = "Lowercase Deloitte username used for resource naming and mandatory username label."
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

variable "gcp_project_id" {
  description = "Shared GCP project ID."
  type        = string
}

variable "gcp_region" {
  description = "GCP region."
  type        = string
  default     = "us-east4"
}

variable "gcp_runtime_sa" {
  description = "Provided shared runtime service account email."
  type        = string
}

variable "image_ref" {
  description = "Full Artifact Registry image reference with @sha256 digest."
  type        = string
  default     = ""
}

variable "repo_url" {
  description = "Repository URL for runbook links in alerts."
  type        = string
  default     = "https://github.com/Deloitte-DT-Training"
}
