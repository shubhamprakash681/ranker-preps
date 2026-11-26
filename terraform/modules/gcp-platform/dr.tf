# ---- Immutable GCS Backup Bucket (7-day retention policy, private, WIF writer grant) ----

resource "google_storage_bucket" "backups" {
  name                        = "${local.prefix}-backups-${var.gcp_project_id}"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  retention_policy {
    retention_period = 604800
    is_locked        = false
  }
}

# Resource-level write access for the shared backup-writer account federated from AWS nwo-backup-task
resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.gcp_backup_writer_sa}"
}

# Resource-level read access & secret access for the shared restore account
resource "google_storage_bucket_iam_member" "restore_reader" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.gcp_restore_sa}"
}

resource "google_secret_manager_secret_iam_member" "restore_db_secret" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gcp_restore_sa}"
}

# ---- Cloud Run Restore Job (1 vCPU / 1 GiB ceiling, Direct VPC egress, shared restore SA) ----

resource "google_cloud_run_v2_job" "restore" {
  name                = "${local.prefix}-restore"
  location            = var.gcp_region
  deletion_protection = false

  template {
    template {
      service_account = var.gcp_restore_sa
      max_retries     = 1
      timeout         = "300s"

      vpc_access {
        egress = "PRIVATE_RANGES_ONLY"
        network_interfaces {
          network    = data.google_compute_network.shared.id
          subnetwork = data.google_compute_subnetwork.private_1.id
        }
      }

      containers {
        image   = local.image
        command = ["python", "-m", "app.dr_restore"]

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }

        env {
          name  = "CLOUD"
          value = "gcp"
        }
        env {
          name  = "SERVICE_NAME"
          value = "orders-restore"
        }
        env {
          name  = "GCP_BACKUP_BUCKET"
          value = google_storage_bucket.backups.name
        }
        env {
          name  = "DB_HOST"
          value = google_sql_database_instance.orders.private_ip_address
        }
        env {
          name  = "DB_NAME"
          value = google_sql_database.orders.name
        }
        env {
          name  = "DB_USER"
          value = google_sql_user.orders.name
        }
        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_password.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.restore_db_secret,
    google_storage_bucket_iam_member.restore_reader,
    google_sql_database.orders,
    google_sql_user.orders,
  ]
}

# Resource-level permission for shared scheduler account to run only this restore job
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  location = google_cloud_run_v2_job.restore.location
  name     = google_cloud_run_v2_job.restore.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.gcp_scheduler_sa}"
}

resource "google_cloud_scheduler_job" "restore" {
  name        = "${local.prefix}-restore-trigger"
  region      = var.gcp_region
  description = "Periodically refresh standby Cloud SQL from newest GCS backup unless promoted"
  schedule    = "*/15 * * * *"
  time_zone   = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "https://${var.gcp_region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.gcp_project_id}/jobs/${google_cloud_run_v2_job.restore.name}:run"

    oauth_token {
      service_account_email = var.gcp_scheduler_sa
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_invoker]
}
