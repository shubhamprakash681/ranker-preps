# ---- Alerts Pub/Sub Channel ----

resource "google_pubsub_topic" "alerts" {
  name = "${local.prefix}-alerts"
}

resource "google_monitoring_notification_channel" "pubsub" {
  display_name = "${local.prefix}-alerts-channel"
  type         = "pubsub"

  labels = {
    topic = google_pubsub_topic.alerts.id
  }

  user_labels = local.common_labels
}

# ---- Cloud Monitoring Service & SLOs (Availability 99.9%, Latency <= 500ms 99%) ----

resource "google_monitoring_custom_service" "orders" {
  service_id   = "${local.prefix}-orders"
  display_name = "Northwind Orders (${local.prefix})"
  user_labels  = local.common_labels
}

resource "google_monitoring_slo" "availability" {
  service             = google_monitoring_custom_service.orders.service_id
  slo_id              = "${local.prefix}-availability-slo"
  display_name        = "99.9% Availability (30d)"
  goal                = 0.999
  rolling_period_days = 30

  request_based_sli {
    good_total_ratio {
      good_service_filter  = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_v2_service.api.name}\" metric.labels.response_code_class!=\"5xx\""
      total_service_filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_v2_service.api.name}\""
    }
  }
}

resource "google_monitoring_slo" "latency" {
  service             = google_monitoring_custom_service.orders.service_id
  slo_id              = "${local.prefix}-latency-slo"
  display_name        = "99% Latency <= 500ms (30d)"
  goal                = 0.99
  rolling_period_days = 30

  request_based_sli {
    distribution_cut {
      distribution_filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_v2_service.api.name}\""
      range {
        min = 0
        max = 500
      }
    }
  }
}

# ---- Multi-Window Burn-Rate Alerts ----

resource "google_monitoring_alert_policy" "page_avail_fast_burn" {
  display_name          = "${local.prefix}-page-avail-fast-burn"
  combiner              = "AND"
  notification_channels = [google_monitoring_notification_channel.pubsub.id]
  user_labels           = local.common_labels

  documentation {
    mime_type = "text/markdown"
    content   = "PAGE: Availability SLO 14.4x fast burn (5m AND 1h windows). First action: inspect Cloud Run API /readyz & logs by trace_id. Runbook: ${var.repo_url}/blob/main/docs/runbooks/availability-burn-rate.md"
  }

  conditions {
    display_name = "5m window burn rate > 14.4x"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"projects/${var.gcp_project_id}/services/${google_monitoring_custom_service.orders.service_id}/serviceLevelObjectives/${google_monitoring_slo.availability.slo_id}\", \"300s\")"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 14.4
      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "1h window burn rate > 14.4x"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"projects/${var.gcp_project_id}/services/${google_monitoring_custom_service.orders.service_id}/serviceLevelObjectives/${google_monitoring_slo.availability.slo_id}\", \"3600s\")"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 14.4
      trigger {
        count = 1
      }
    }
  }

  depends_on = [google_monitoring_slo.availability]
}

resource "google_monitoring_alert_policy" "ticket_avail_slow_burn" {
  display_name = "${local.prefix}-ticket-avail-slow-burn"
  combiner     = "AND"
  user_labels  = local.common_labels

  documentation {
    mime_type = "text/markdown"
    content   = "TICKET: Availability SLO 3x slow burn (30m AND 6h windows). Runbook: ${var.repo_url}/blob/main/docs/runbooks/availability-burn-rate.md"
  }

  conditions {
    display_name = "30m window burn rate > 3x"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"projects/${var.gcp_project_id}/services/${google_monitoring_custom_service.orders.service_id}/serviceLevelObjectives/${google_monitoring_slo.availability.slo_id}\", \"1800s\")"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 3.0
      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "6h window burn rate > 3x"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"projects/${var.gcp_project_id}/services/${google_monitoring_custom_service.orders.service_id}/serviceLevelObjectives/${google_monitoring_slo.availability.slo_id}\", \"21600s\")"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 3.0
      trigger {
        count = 1
      }
    }
  }

  depends_on = [google_monitoring_slo.availability]
}

resource "google_monitoring_alert_policy" "page_latency_fast_burn" {
  display_name          = "${local.prefix}-page-latency-fast-burn"
  combiner              = "AND"
  notification_channels = [google_monitoring_notification_channel.pubsub.id]
  user_labels           = local.common_labels

  documentation {
    mime_type = "text/markdown"
    content   = "PAGE: Latency SLO 14.4x fast burn (5m AND 1h windows). First action: inspect db_query_duration_seconds & Cloud SQL CPU. Runbook: ${var.repo_url}/blob/main/docs/runbooks/latency-burn-rate.md"
  }

  conditions {
    display_name = "5m window latency burn rate > 14.4x"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"projects/${var.gcp_project_id}/services/${google_monitoring_custom_service.orders.service_id}/serviceLevelObjectives/${google_monitoring_slo.latency.slo_id}\", \"300s\")"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 14.4
      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "1h window latency burn rate > 14.4x"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"projects/${var.gcp_project_id}/services/${google_monitoring_custom_service.orders.service_id}/serviceLevelObjectives/${google_monitoring_slo.latency.slo_id}\", \"3600s\")"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 14.4
      trigger {
        count = 1
      }
    }
  }

  depends_on = [google_monitoring_slo.latency]
}

# ---- Cause-Based Alerts (Ticket-Only: Queue Age, DLQ Depth, Memory, Cloud SQL) ----

resource "google_monitoring_alert_policy" "cause_pubsub_queue_age" {
  display_name = "${local.prefix}-cause-pubsub-queue-age"
  combiner     = "OR"
  user_labels  = local.common_labels

  documentation {
    mime_type = "text/markdown"
    content   = "TICKET (Cause): Pub/Sub oldest unacked message age > 120s. Inspect Cloud Run Worker."
  }

  conditions {
    display_name = "Pub/Sub oldest unacked message age > 120s"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\" resource.labels.subscription_id=\"${google_pubsub_subscription.orders.name}\""
      duration        = "120s"
      comparison      = "COMPARISON_GT"
      threshold_value = 120
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
}

resource "google_monitoring_alert_policy" "cause_pubsub_dlq_depth" {
  display_name = "${local.prefix}-cause-pubsub-dlq-depth"
  combiner     = "OR"
  user_labels  = local.common_labels

  documentation {
    mime_type = "text/markdown"
    content   = "TICKET (Cause): Messages in Pub/Sub Dead-Letter subscription (> 0). Inspect worker failure logs by trace_id."
  }

  conditions {
    display_name = "Pub/Sub DLQ undelivered messages > 0"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" resource.type=\"pubsub_subscription\" resource.labels.subscription_id=\"${google_pubsub_subscription.orders_dlq.name}\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
}

resource "google_monitoring_alert_policy" "cause_cloudrun_memory" {
  display_name = "${local.prefix}-cause-cloudrun-memory"
  combiner     = "OR"
  user_labels  = local.common_labels

  documentation {
    mime_type = "text/markdown"
    content   = "TICKET (Cause): Cloud Run API memory utilization > 85%. Check for memory leak."
  }

  conditions {
    display_name = "Cloud Run API memory > 85%"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/container/memory/utilizations\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_v2_service.api.name}\""
      duration        = "180s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.85
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
    }
  }
}

resource "google_monitoring_alert_policy" "cause_cloudsql_cpu" {
  display_name = "${local.prefix}-cause-cloudsql-cpu"
  combiner     = "OR"
  user_labels  = local.common_labels

  documentation {
    mime_type = "text/markdown"
    content   = "TICKET (Cause): Cloud SQL CPU utilization > 80%."
  }

  conditions {
    display_name = "Cloud SQL CPU > 80%"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\" resource.labels.database_id=\"${var.gcp_project_id}:${google_sql_database_instance.orders.name}\""
      duration        = "180s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
}

# ---- Cloud Monitoring Dashboard ----

resource "google_monitoring_dashboard" "main" {
  dashboard_json = jsonencode({
    displayName = "${local.prefix}-dashboard"
    gridLayout  = {
      columns = 2
      widgets = [
        {
          title   = "Cloud Run API Request Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_v2_service.api.name}\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["metric.label.response_code_class"]
                  }
                }
              }
            }]
          }
        },
        {
          title   = "Cloud Run API Latency (p95)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter      = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_v2_service.api.name}\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_PERCENTILE_95"
                    crossSeriesReducer = "REDUCE_MAX"
                  }
                }
              }
            }]
          }
        },
        {
          title   = "Pub/Sub Oldest Unacked Age & DLQ Depth"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\" resource.labels.subscription_id=\"${google_pubsub_subscription.orders.name}\""
                  }
                }
              },
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" resource.type=\"pubsub_subscription\" resource.labels.subscription_id=\"${google_pubsub_subscription.orders_dlq.name}\""
                  }
                }
              }
            ]
          }
        },
        {
          title   = "Cloud SQL CPU & Connections"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\" resource.labels.database_id=\"${var.gcp_project_id}:${google_sql_database_instance.orders.name}\""
                  }
                }
              },
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\" resource.type=\"cloudsql_database\" resource.labels.database_id=\"${var.gcp_project_id}:${google_sql_database_instance.orders.name}\""
                  }
                }
              }
            ]
          }
        }
      ]
    }
  })
}
