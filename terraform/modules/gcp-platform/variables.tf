variable "username" {
  description = "Lowercase Deloitte username for mandatory username label on Cloud SQL user_labels."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix (nwo-<username>)."
  type        = string
}

variable "env" {
  description = "Environment name (dev or prod)."
  type        = string
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
  description = "Provided shared runtime service account email for Cloud Run API and Worker."
  type        = string
}

variable "image_ref" {
  description = "Full Artifact Registry image reference with immutable @sha256 digest."
  type        = string
  default     = ""
}

variable "api_min_instances" {
  description = "Minimum Cloud Run API instances (0 or 1)."
  type        = number
  default     = 0
}

variable "api_max_instances" {
  description = "Maximum Cloud Run API instances (ceiling: 5)."
  type        = number
  default     = 3
}

variable "worker_min_instances" {
  description = "Minimum Cloud Run Worker instances (1 keeps background Pub/Sub consumer active)."
  type        = number
  default     = 1
}

variable "worker_max_instances" {
  description = "Maximum Cloud Run Worker instances (ceiling: 3)."
  type        = number
  default     = 2
}
