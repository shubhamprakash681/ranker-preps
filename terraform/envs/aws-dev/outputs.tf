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

output "origin_verify_secret" {
  description = "Shared secret for CloudFront X-Origin-Verify header."
  value       = module.aws_platform.origin_verify_secret
  sensitive   = true
}

output "backups_bucket_name" {
  description = "Immutable S3 backups bucket name."
  value       = module.aws_platform.backups_bucket_name
}

output "backup_task_definition_arn" {
  description = "Backup ECS task definition ARN."
  value       = module.aws_platform.backup_task_definition_arn
}

output "private_subnet_ids" {
  description = "Shared private subnet IDs."
  value       = module.aws_platform.private_subnet_ids
}

output "ecs_security_group_id" {
  description = "ECS security group ID."
  value       = module.aws_platform.ecs_security_group_id
}
