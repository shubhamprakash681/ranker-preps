locals {
  prefix = "${var.name_prefix}-${var.env}"
  image  = var.image_ref != "" ? var.image_ref : "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}/orders:latest"
  common_labels = {
    username    = var.username
    environment = var.env
    managed_by  = "terraform"
  }
}

data "google_project" "current" {
  project_id = var.gcp_project_id
}

data "google_compute_network" "shared" {
  name = "hu-devops-26-nov-vpc"
}

data "google_compute_subnetwork" "private_1" {
  name   = "hu-devops-26-nov-private-use4-1"
  region = var.gcp_region
}
