# ---- GCP Cloud Monitoring Uptime Check & Alert Against Public Hostname ----

resource "google_monitoring_uptime_check_config" "public_endpoint" {
  display_name = "${local.prefix}-public-uptime"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/version"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.gcp_project_id
      host       = aws_cloudfront_distribution.main.domain_name
    }
  }

  content_matchers {
    content = "\"cloud\""
    matcher = "CONTAINS_STRING"
  }

  user_labels = {
    username    = var.username
    environment = var.env
    managed_by  = "terraform"
  }
}

resource "google_monitoring_alert_policy" "public_endpoint_down" {
  display_name = "${local.prefix}-page-endpoint-down"
  combiner     = "OR"

  user_labels = {
    username    = var.username
    environment = var.env
    managed_by  = "terraform"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "PAGE: Synthetic uptime check against public hostname https://${aws_cloudfront_distribution.main.domain_name}/version failed. First action: run probe & check active origin /readyz. Runbook: ${var.repo_url}/blob/main/docs/runbooks/endpoint-down.md"
  }

  conditions {
    display_name = "Public HTTPS /version uptime check failing"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" metric.label.check_id=\"${google_monitoring_uptime_check_config.public_endpoint.uptime_check_id}\""
      duration        = "120s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      trigger {
        count = 1
      }
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
      }
    }
  }
}
