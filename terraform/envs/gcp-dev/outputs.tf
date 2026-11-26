output "artifact_registry_url" {
  description = "Artifact Registry repository URL."
  value       = module.gcp_platform.artifact_registry_url
}

output "api_url" {
  description = "Cloud Run API service URL."
  value       = module.gcp_platform.api_url
}

output "receipts_bucket_name" {
  description = "GCS receipts bucket name."
  value       = module.gcp_platform.receipts_bucket_name
}

output "pubsub_topic_id" {
  description = "Pub/Sub orders topic ID."
  value       = module.gcp_platform.pubsub_topic_id
}

output "pubsub_subscription_id" {
  description = "Pub/Sub orders subscription ID."
  value       = module.gcp_platform.pubsub_subscription_id
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL PostgreSQL instance name."
  value       = module.gcp_platform.cloud_sql_instance_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP."
  value       = module.gcp_platform.cloud_sql_private_ip
}
