terraform {
  required_version = ">= 1.10.0, < 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.15.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      username    = var.username
      environment = var.env
      managed_by  = "terraform"
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
