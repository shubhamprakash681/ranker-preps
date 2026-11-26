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
