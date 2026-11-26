# ---- SNS Alerts Topic (KMS-encrypted) ----

resource "aws_sns_topic" "alerts" {
  name              = "${local.prefix}-alerts"
  kms_master_key_id = aws_kms_key.main.arn

  tags = {
    Name = "${local.prefix}-alerts"
  }
}

# ---- Multi-Window Burn-Rate Alerts (Availability 99.9% SLO & Latency <= 500ms p99 SLO) ----
# Fast burn (14.4x): 5m AND 1h windows -> Pages on-call with runbook link + first action.
# Slow burn (3.0x): 30m AND 6h windows -> Ticket-only (no page).

resource "aws_cloudwatch_metric_alarm" "avail_burn_5m" {
  alarm_name          = "${local.prefix}-slo-avail-burn-5m"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0.0144
  treat_missing_data  = "notBreaching"
  alarm_description   = "5m window Availability fast burn (>14.4x budget for 99.9% SLO)"

  metric_query {
    id          = "e_err"
    expression  = "IF(m_req > 0, (FILL(m_t5xx, 0) + FILL(m_e5xx, 0)) / m_req, 0)"
    label       = "5xx Error Rate (5m)"
    return_data = true
  }

  metric_query {
    id = "m_req"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_t5xx"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_e5xx"
    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  tags = {
    Name = "${local.prefix}-slo-avail-burn-5m"
  }
}

resource "aws_cloudwatch_metric_alarm" "avail_burn_1h" {
  alarm_name          = "${local.prefix}-slo-avail-burn-1h"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0.0144
  treat_missing_data  = "notBreaching"
  alarm_description   = "1h window Availability fast burn (>14.4x budget for 99.9% SLO)"

  metric_query {
    id          = "e_err"
    expression  = "IF(m_req > 0, (FILL(m_t5xx, 0) + FILL(m_e5xx, 0)) / m_req, 0)"
    label       = "5xx Error Rate (1h)"
    return_data = true
  }

  metric_query {
    id = "m_req"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 3600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_t5xx"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 3600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_e5xx"
    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 3600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  tags = {
    Name = "${local.prefix}-slo-avail-burn-1h"
  }
}

resource "aws_cloudwatch_composite_alarm" "page_avail_fast_burn" {
  alarm_name        = "${local.prefix}-page-avail-fast-burn"
  alarm_description = "PAGE: Availability SLO 14.4x fast burn (5m AND 1h windows). First action: inspect ECS /readyz & ALB 5XX logs by trace_id. Runbook: ${var.repo_url}/blob/main/docs/runbooks/availability-burn-rate.md"
  alarm_rule        = "ALARM(\"${aws_cloudwatch_metric_alarm.avail_burn_5m.alarm_name}\") AND ALARM(\"${aws_cloudwatch_metric_alarm.avail_burn_1h.alarm_name}\")"
  alarm_actions     = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.prefix}-page-avail-fast-burn"
  }
}

resource "aws_cloudwatch_metric_alarm" "avail_burn_30m" {
  alarm_name          = "${local.prefix}-slo-avail-burn-30m"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0.003
  treat_missing_data  = "notBreaching"
  alarm_description   = "30m window Availability slow burn (>3x budget for 99.9% SLO)"

  metric_query {
    id          = "e_err"
    expression  = "IF(m_req > 0, (FILL(m_t5xx, 0) + FILL(m_e5xx, 0)) / m_req, 0)"
    label       = "5xx Error Rate (30m)"
    return_data = true
  }

  metric_query {
    id = "m_req"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 1800
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_t5xx"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 1800
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_e5xx"
    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 1800
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  tags = {
    Name = "${local.prefix}-slo-avail-burn-30m"
  }
}

resource "aws_cloudwatch_metric_alarm" "avail_burn_6h" {
  alarm_name          = "${local.prefix}-slo-avail-burn-6h"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0.003
  treat_missing_data  = "notBreaching"
  alarm_description   = "6h window Availability slow burn (>3x budget for 99.9% SLO)"

  metric_query {
    id          = "e_err"
    expression  = "IF(m_req > 0, (FILL(m_t5xx, 0) + FILL(m_e5xx, 0)) / m_req, 0)"
    label       = "5xx Error Rate (6h)"
    return_data = true
  }

  metric_query {
    id = "m_req"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 21600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_t5xx"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 21600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_e5xx"
    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 21600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }

  tags = {
    Name = "${local.prefix}-slo-avail-burn-6h"
  }
}

resource "aws_cloudwatch_composite_alarm" "ticket_avail_slow_burn" {
  alarm_name        = "${local.prefix}-ticket-avail-slow-burn"
  alarm_description = "TICKET: Availability SLO 3x slow burn (30m AND 6h windows). Review error logs & error budget. Runbook: ${var.repo_url}/blob/main/docs/runbooks/availability-burn-rate.md"
  alarm_rule        = "ALARM(\"${aws_cloudwatch_metric_alarm.avail_burn_30m.alarm_name}\") AND ALARM(\"${aws_cloudwatch_metric_alarm.avail_burn_6h.alarm_name}\")"

  tags = {
    Name = "${local.prefix}-ticket-avail-slow-burn"
  }
}

resource "aws_cloudwatch_metric_alarm" "latency_burn_5m" {
  alarm_name          = "${local.prefix}-slo-latency-burn-5m"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 0.5
  treat_missing_data  = "notBreaching"
  alarm_description   = "5m window Latency SLO breach (p99 > 500ms)"

  dimensions = {
    LoadBalancer = aws_lb.api.arn_suffix
  }

  tags = {
    Name = "${local.prefix}-slo-latency-burn-5m"
  }
}

resource "aws_cloudwatch_metric_alarm" "latency_burn_1h" {
  alarm_name          = "${local.prefix}-slo-latency-burn-1h"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 3600
  extended_statistic  = "p99"
  threshold           = 0.5
  treat_missing_data  = "notBreaching"
  alarm_description   = "1h window Latency SLO breach (p99 > 500ms)"

  dimensions = {
    LoadBalancer = aws_lb.api.arn_suffix
  }

  tags = {
    Name = "${local.prefix}-slo-latency-burn-1h"
  }
}

resource "aws_cloudwatch_composite_alarm" "page_latency_fast_burn" {
  alarm_name        = "${local.prefix}-page-latency-fast-burn"
  alarm_description = "PAGE: Latency SLO p99 > 500ms (5m AND 1h windows). First action: check /metrics db_query_duration_seconds & RDS/ECS CPU. Runbook: ${var.repo_url}/blob/main/docs/runbooks/latency-burn-rate.md"
  alarm_rule        = "ALARM(\"${aws_cloudwatch_metric_alarm.latency_burn_5m.alarm_name}\") AND ALARM(\"${aws_cloudwatch_metric_alarm.latency_burn_1h.alarm_name}\")"
  alarm_actions     = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${local.prefix}-page-latency-fast-burn"
  }
}

# ---- Cause-Based Alerts (Ticket-Only: Queue Age, DLQ Depth, Memory, Database) ----

resource "aws_cloudwatch_metric_alarm" "cause_sqs_queue_age" {
  alarm_name          = "${local.prefix}-cause-sqs-queue-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 120
  treat_missing_data  = "notBreaching"
  alarm_description   = "TICKET (Cause): SQS oldest message age > 120s. Check ECS Worker health & logs."

  dimensions = {
    QueueName = aws_sqs_queue.orders.name
  }

  tags = {
    Name = "${local.prefix}-cause-sqs-queue-age"
  }
}

resource "aws_cloudwatch_metric_alarm" "cause_sqs_dlq_depth" {
  alarm_name          = "${local.prefix}-cause-sqs-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "TICKET (Cause): Messages in SQS Dead-Letter Queue (> 0). Inspect worker failure logs by trace_id."

  dimensions = {
    QueueName = aws_sqs_queue.orders_dlq.name
  }

  tags = {
    Name = "${local.prefix}-cause-sqs-dlq-depth"
  }
}

resource "aws_cloudwatch_metric_alarm" "cause_ecs_memory" {
  alarm_name          = "${local.prefix}-cause-ecs-api-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_description   = "TICKET (Cause): ECS API memory > 85%. Check for memory leak or OOM restarts."

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.api.name
  }

  tags = {
    Name = "${local.prefix}-cause-ecs-api-memory"
  }
}

resource "aws_cloudwatch_metric_alarm" "cause_rds_cpu" {
  alarm_name          = "${local.prefix}-cause-rds-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "TICKET (Cause): RDS PostgreSQL CPU > 80%. Check slow queries and DB connections."

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.orders.identifier
  }

  tags = {
    Name = "${local.prefix}-cause-rds-cpu"
  }
}

# ---- CloudWatch Dashboard ----

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "metric"
        x          = 0
        y          = 0
        width      = 8
        height     = 6
        properties = {
          title   = "ALB Requests & 5XX Errors"
          region  = var.aws_region
          stat    = "Sum"
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.api.arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."]
          ]
        }
      },
      {
        type       = "metric"
        x          = 8
        y          = 0
        width      = 8
        height     = 6
        properties = {
          title   = "ALB Latency (p50 / p95 / p99)"
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.api.arn_suffix, { stat = "p50" }],
            ["...", { stat = "p95" }],
            ["...", { stat = "p99" }]
          ]
        }
      },
      {
        type       = "metric"
        x          = 16
        y          = 0
        width      = 8
        height     = 6
        properties = {
          title   = "SQS Queue Depth, Age & DLQ"
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.orders.name],
            [".", "ApproximateAgeOfOldestMessage", ".", "."],
            [".", "ApproximateNumberOfMessagesVisible", ".", aws_sqs_queue.orders_dlq.name]
          ]
        }
      },
      {
        type       = "metric"
        x          = 0
        y          = 6
        width      = 12
        height     = 6
        properties = {
          title   = "ECS API & Worker CPU / Memory"
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.api.name],
            [".", "MemoryUtilization", ".", ".", ".", "."],
            [".", "CPUUtilization", ".", ".", "ServiceName", aws_ecs_service.worker.name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
        }
      },
      {
        type       = "metric"
        x          = 12
        y          = 6
        width      = 12
        height     = 6
        properties = {
          title   = "RDS PostgreSQL CPU & Connections"
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.orders.identifier],
            [".", "DatabaseConnections", ".", "."],
            [".", "ReadLatency", ".", "."]
          ]
        }
      }
    ]
  })
}
