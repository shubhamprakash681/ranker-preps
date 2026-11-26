output "artifact_registry_url" {
  description = "Artifact Registry Docker repository URL."
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "api_url" {
  description = "Cloud Run API service URL."
  value       = google_cloud_run_v2_service.api.uri
}

output "api_service_name" {
  description = "Cloud Run API service name."
  value       = google_cloud_run_v2_service.api.name
}

output "worker_service_name" {
  description = "Cloud Run Worker service name."
  value       = google_cloud_run_v2_service.worker.name
}

output "receipts_bucket_name" {
  description = "GCS receipts bucket name."
  value       = google_storage_bucket.receipts.name
}

output "pubsub_topic_id" {
  description = "Pub/Sub orders topic path."
  value       = google_pubsub_topic.orders.id
}

output "pubsub_subscription_id" {
  description = "Pub/Sub orders subscription path."
  value       = google_pubsub_subscription.orders.id
}

output "pubsub_dlq_topic_id" {
  description = "Pub/Sub dead-letter topic path."
  value       = google_pubsub_topic.orders_dlq.id
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL PostgreSQL instance name."
  value       = google_sql_database_instance.orders.name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL PostgreSQL private IP address."
  value       = google_sql_database_instance.orders.private_ip_address
}

output "db_secret_id" {
  description = "Secret Manager secret ID for database password."
  value       = google_secret_manager_secret.db_password.secret_id
}
