# Bootstrap verification for Task 2 (CI/CD, WIF, GCS remote state locking, shared VPC data lookup).
# Replaced with module "gcp_platform" in Task 3.

data "google_compute_network" "shared" {
  name = "hu-devops-26-nov-vpc"
}

output "shared_vpc_id" {
  description = "ID of the pre-built shared GCP VPC."
  value       = data.google_compute_network.shared.id
}

output "environment" {
  description = "Target environment."
  value       = "${var.name_prefix}-${var.env}"
}
