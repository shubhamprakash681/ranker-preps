resource "google_artifact_registry_repository" "app" {
  location      = var.gcp_region
  repository_id = "${local.prefix}-orders"
  description   = "Container repository for ${local.prefix}"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "runtime_reader" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.gcp_runtime_sa}"
}

# ---- GCS Receipts Bucket (private, public access prevented, uniform access, versioned) ----

resource "google_storage_bucket" "receipts" {
  name                        = "${local.prefix}-receipts-${var.gcp_project_id}"
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_member" "runtime_receipts" {
  bucket = google_storage_bucket.receipts.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${var.gcp_runtime_sa}"
}

# ---- Pub/Sub Topic + Dead-Letter Topic & Subscriptions ----

resource "google_pubsub_topic" "orders_dlq" {
  name = "${local.prefix}-orders-dlq"
}

resource "google_pubsub_subscription" "orders_dlq" {
  name                       = "${local.prefix}-orders-dlq-sub"
  topic                      = google_pubsub_topic.orders_dlq.id
  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "orders" {
  name = "${local.prefix}-orders"
}

resource "google_pubsub_subscription" "orders" {
  name                       = "${local.prefix}-orders-sub"
  topic                      = google_pubsub_topic.orders.id
  ack_deadline_seconds       = 30
  message_retention_duration = "345600s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.orders_dlq.id
    max_delivery_attempts = 5
  }
}

# Resource-level IAM for the shared runtime service account (own resources only)
resource "google_pubsub_topic_iam_member" "runtime_publisher" {
  topic  = google_pubsub_topic.orders.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${var.gcp_runtime_sa}"
}

resource "google_pubsub_subscription_iam_member" "runtime_subscriber" {
  subscription = google_pubsub_subscription.orders.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.gcp_runtime_sa}"
}

# Resource-level IAM for Google-managed Pub/Sub service agent to forward dead-lettered messages
resource "google_pubsub_topic_iam_member" "pubsub_dlq_publisher" {
  topic  = google_pubsub_topic.orders_dlq.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "pubsub_dlq_subscriber" {
  subscription = google_pubsub_subscription.orders.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
