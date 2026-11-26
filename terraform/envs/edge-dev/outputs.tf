output "cloudfront_domain_name" {
  description = "Public HTTPS hostname issued by CloudFront."
  value       = module.edge.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.edge.cloudfront_distribution_id
}

output "kvs_arn" {
  description = "CloudFront KeyValueStore ARN."
  value       = module.edge.kvs_arn
}

output "kvs_name" {
  description = "CloudFront KeyValueStore name."
  value       = module.edge.kvs_name
}
