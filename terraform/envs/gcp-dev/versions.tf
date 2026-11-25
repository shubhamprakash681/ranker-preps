terraform {
  required_version = ">= 1.10.0, < 1.12.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.15.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  default_labels = {
    username    = var.username
    environment = var.env
    managed_by  = "terraform"
  }
}
