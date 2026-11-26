# ---- Cloud Run API Service (Direct VPC egress, invoker IAM disabled per org-policy alternative, no allUsers) ----

resource "google_cloud_run_v2_service" "api" {
  name                 = "${local.prefix}-api"
  location             = var.gcp_region
  ingress              = "INGRESS_TRAFFIC_ALL"
  invoker_iam_disabled = true
  deletion_protection  = false

  template {
    service_account = var.gcp_runtime_sa

    scaling {
      min_instance_count = var.api_min_instances
      max_instance_count = var.api_max_instances
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = data.google_compute_network.shared.id
        subnetwork = data.google_compute_subnetwork.private_1.id
      }
    }

    containers {
      image = local.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        cpu_idle = true
      }

      env {
        name  = "CLOUD"
        value = "gcp"
      }
      env {
        name  = "SERVICE_NAME"
        value = "orders-api"
      }
      env {
        name  = "QUEUE_BACKEND"
        value = "pubsub"
      }
      env {
        name  = "QUEUE_NAME"
        value = google_pubsub_subscription.orders.id
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.orders.id
      }
      env {
        name  = "STORAGE_BACKEND"
        value = "gcs"
      }
      env {
        name  = "STORAGE_TARGET"
        value = google_storage_bucket.receipts.name
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

      startup_probe {
        http_get {
          path = "/readyz"
          port = 8080
        }
        initial_delay_seconds = 5
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 5
      }

      liveness_probe {
        http_get {
          path = "/healthz"
          port = 8080
        }
        period_seconds    = 30
        timeout_seconds   = 5
        failure_threshold = 3
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.runtime_db_secret,
    google_sql_database.orders,
    google_sql_user.orders,
  ]
}

# ---- Cloud Run Worker Service (Internal only, invoker IAM enabled, CPU always allocated for Pub/Sub loop) ----

resource "google_cloud_run_v2_service" "worker" {
  name                 = "${local.prefix}-worker"
  location             = var.gcp_region
  ingress              = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  invoker_iam_disabled = false
  deletion_protection  = false

  template {
    service_account = var.gcp_runtime_sa

    scaling {
      min_instance_count = var.worker_min_instances
      max_instance_count = var.worker_max_instances
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = data.google_compute_network.shared.id
        subnetwork = data.google_compute_subnetwork.private_1.id
      }
    }

    containers {
      image   = local.image
      command = ["python", "-m", "app.worker"]

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = false
      }

      env {
        name  = "CLOUD"
        value = "gcp"
      }
      env {
        name  = "SERVICE_NAME"
        value = "orders-worker"
      }
      env {
        name  = "QUEUE_BACKEND"
        value = "pubsub"
      }
      env {
        name  = "QUEUE_NAME"
        value = google_pubsub_subscription.orders.id
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.orders.id
      }
      env {
        name  = "STORAGE_BACKEND"
        value = "gcs"
      }
      env {
        name  = "STORAGE_TARGET"
        value = google_storage_bucket.receipts.name
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

      startup_probe {
        http_get {
          path = "/"
          port = 8080
        }
        initial_delay_seconds = 5
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 5
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.runtime_db_secret,
    google_sql_database.orders,
    google_sql_user.orders,
  ]
}
