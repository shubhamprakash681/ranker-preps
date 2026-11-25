# Bootstrap verification for Task 2 (CI/CD, OIDC, remote state locking, shared VPC data lookup).
# Replaced with module "aws_platform" in Task 1.

data "aws_caller_identity" "current" {}

data "aws_vpc" "shared" {
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-vpc"]
  }
}

output "shared_vpc_id" {
  description = "ID of the pre-built shared AWS VPC."
  value       = data.aws_vpc.shared.id
}

output "environment" {
  description = "Target environment."
  value       = "${var.name_prefix}-${var.env}"
}
