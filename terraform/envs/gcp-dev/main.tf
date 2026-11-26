module "gcp_platform" {
  source = "../../modules/gcp-platform"

  username       = var.username
  name_prefix    = var.name_prefix
  env            = var.env
  gcp_project_id = var.gcp_project_id
  gcp_region     = var.gcp_region
  gcp_runtime_sa = var.gcp_runtime_sa
  image_ref      = var.image_ref

  # Deliberate warm-standby sizing within approved ceilings (API <= 5, Worker <= 3)
  api_min_instances    = 0
  api_max_instances    = 3
  worker_min_instances = 1
  worker_max_instances = 2
  repo_url             = var.repo_url
  gcp_restore_sa       = var.gcp_restore_sa
  gcp_scheduler_sa     = var.gcp_scheduler_sa
  gcp_backup_writer_sa = var.gcp_backup_writer_sa
}
