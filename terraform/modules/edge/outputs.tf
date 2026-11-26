output "cloudfront_domain_name" {
  description = "Public HTTPS hostname issued by CloudFront."
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.main.id
}

output "kvs_arn" {
  description = "CloudFront KeyValueStore ARN for instant traffic switching."
  value       = aws_cloudfront_key_value_store.routing.arn
}

output "kvs_name" {
  description = "CloudFront KeyValueStore name."
  value       = aws_cloudfront_key_value_store.routing.name
}
