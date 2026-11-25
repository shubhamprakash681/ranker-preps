output "ecr_repository_url" {
  description = "ECR repository URL for container pushes."
  value       = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.api.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.api.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB for CloudWatch metrics."
  value       = aws_lb.api.arn_suffix
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the ALB Target Group for CloudWatch metrics."
  value       = aws_lb_target_group.api.arn_suffix
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "api_service_name" {
  description = "ECS API service name."
  value       = aws_ecs_service.api.name
}

output "worker_service_name" {
  description = "ECS Worker service name."
  value       = aws_ecs_service.worker.name
}

output "receipts_bucket_name" {
  description = "S3 receipts bucket name."
  value       = aws_s3_bucket.receipts.id
}

output "sqs_queue_url" {
  description = "SQS orders queue URL."
  value       = aws_sqs_queue.orders.url
}

output "sqs_queue_name" {
  description = "SQS orders queue name."
  value       = aws_sqs_queue.orders.name
}

output "sqs_dlq_name" {
  description = "SQS dead-letter queue name."
  value       = aws_sqs_queue.orders_dlq.name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint address."
  value       = aws_db_instance.orders.address
}

output "rds_identifier" {
  description = "RDS PostgreSQL instance identifier."
  value       = aws_db_instance.orders.identifier
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for database credentials."
  value       = aws_secretsmanager_secret.db.arn
}

output "kms_key_arn" {
  description = "Customer-managed KMS key ARN."
  value       = aws_kms_key.main.arn
}

output "api_log_group_name" {
  description = "CloudWatch log group for API."
  value       = aws_cloudwatch_log_group.api.name
}

output "worker_log_group_name" {
  description = "CloudWatch log group for Worker."
  value       = aws_cloudwatch_log_group.worker.name
}

output "private_subnet_ids" {
  description = "Shared private subnet IDs."
  value       = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
}

output "ecs_security_group_id" {
  description = "ECS security group ID."
  value       = aws_security_group.ecs.id
}
