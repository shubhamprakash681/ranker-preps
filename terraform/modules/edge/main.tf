locals {
  prefix = "${var.name_prefix}-${var.env}"
}

resource "aws_cloudfront_key_value_store" "routing" {
  name    = "${local.prefix}-kvs"
  comment = "Dynamic AWS/GCP traffic split weight (0..100) for ${local.prefix}"
}

resource "aws_cloudfrontkeyvaluestore_key" "aws_weight" {
  key_value_store_arn = aws_cloudfront_key_value_store.routing.arn
  key                 = "aws_weight"
  value               = "100"

  # Allow runtime traffic switches without Terraform overwriting the live weight.
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_cloudfront_function" "router" {
  name                         = "${local.prefix}-router"
  runtime                      = "cloudfront-js-2.0"
  comment                      = "Weighted origin routing between AWS ALB and GCP Cloud Run"
  publish                      = true
  key_value_store_associations = [aws_cloudfront_key_value_store.routing.arn]
  code                         = file("${path.module}/router.js")
}

# CloudFront default certificate is required (no custom domain/ACM cert), and WAFv2 is outside the allowed CI IAM services list.
#trivy:ignore:AVD-AWS-0010
#trivy:ignore:AVD-AWS-0011
#trivy:ignore:AVD-AWS-0012
resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Northwind Orders multi-cloud HTTPS edge (${local.prefix})"
  price_class     = "PriceClass_100"

  origin {
    origin_id   = "aws-origin"
    domain_name = var.aws_alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_secret
    }
  }

  origin {
    origin_id   = "gcp-origin"
    domain_name = var.gcp_api_host

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "aws-origin"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Managed-CachingDisabled & Managed-AllViewerExceptHostHeader
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.router.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.prefix}-edge"
  }
}
