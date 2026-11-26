module "aws_platform" {
  source = "../../modules/aws-platform"

  name_prefix  = var.name_prefix
  env          = var.env
  aws_region   = var.aws_region
  image_digest = var.image_digest

  # Deliberate dev sizing within approved ceilings (API ceiling: 512/1024 x4, Worker ceiling: 256/512 x2)
  api_cpu                     = 256
  api_memory                  = 512
  api_min_capacity            = 2
  api_max_capacity            = 4
  worker_cpu                  = 256
  worker_memory               = 512
  worker_min_capacity         = 1
  worker_max_capacity         = 2
  log_retention_days          = 14
  skip_final_snapshot         = true
  secret_recovery_window_days = 0
  enable_edge_only            = true
  repo_url                    = var.repo_url
  aws_backup_task_role_arn    = var.aws_backup_task_role_arn
  gcp_aws_wif_provider        = var.gcp_aws_wif_provider
  gcp_backup_writer_sa        = var.gcp_backup_writer_sa
  gcp_project_id              = var.gcp_project_id
}
