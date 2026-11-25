output "ecr_repository_url" {
  description = "ECR repository URL."
  value       = module.aws_platform.ecr_repository_url
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name."
  value       = module.aws_platform.alb_dns_name
}

output "receipts_bucket_name" {
  description = "S3 receipts bucket name."
  value       = module.aws_platform.receipts_bucket_name
}

output "sqs_queue_url" {
  description = "SQS orders queue URL."
  value       = module.aws_platform.sqs_queue_url
}

output "sqs_dlq_name" {
  description = "SQS dead-letter queue name."
  value       = module.aws_platform.sqs_dlq_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = module.aws_platform.rds_endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.aws_platform.ecs_cluster_name
}
