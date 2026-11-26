resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.prefix}-db-password"

  replication {
    user_managed {
      replicas {
        location = var.gcp_region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

resource "google_secret_manager_secret_iam_member" "runtime_db_secret" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gcp_runtime_sa}"
}

# Cloud SQL PostgreSQL 16 (private IP only, db-f1-micro, zonal, ENTERPRISE edition explicitly, PITR enabled)
resource "google_sql_database_instance" "orders" {
  name                = "${local.prefix}-pg"
  database_version    = "POSTGRES_16"
  region              = var.gcp_region
  deletion_protection = false

  settings {
    tier                  = "db-f1-micro"
    edition               = "ENTERPRISE"
    availability_type     = "ZONAL"
    disk_size             = 10
    disk_type             = "PD_SSD"
    disk_autoresize       = true
    disk_autoresize_limit = 20
    user_labels           = local.common_labels

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.shared.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }
  }
}

resource "google_sql_database" "orders" {
  name     = "orders"
  instance = google_sql_database_instance.orders.name
}

resource "google_sql_user" "orders" {
  name     = "orders"
  instance = google_sql_database_instance.orders.name
  password = random_password.db.result
}
