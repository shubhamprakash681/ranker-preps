# ---- Migrated Cloud-Native Nightly Settlement Job (Stretch) ----

resource "aws_cloudwatch_log_group" "settlement" {
  name              = "${local.prefix}-settlement"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name = "${local.prefix}-settlement"
  }
}

resource "aws_ecs_task_definition" "settlement" {
  family                   = "${local.prefix}-settlement"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "settlement"
      image     = local.image
      essential = true
      command   = ["python", "-m", "app.settlement"]
      environment = [
        { name = "CLOUD", value = "aws" },
        { name = "SERVICE_NAME", value = "orders-settlement" },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "STORAGE_BACKEND", value = "s3" },
        { name = "STORAGE_TARGET", value = aws_s3_bucket.receipts.id },
        { name = "DB_HOST", value = aws_db_instance.orders.address },
        { name = "DB_NAME", value = "orders" },
        { name = "DB_USER", value = "orders" },
      ]
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db.arn}:password::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.settlement.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "settlement"
        }
      }
    }
  ])

  tags = {
    Name = "${local.prefix}-settlement"
  }
}

resource "aws_scheduler_schedule" "settlement" {
  name        = "${local.prefix}-settlement-nightly"
  group_name  = aws_scheduler_schedule_group.main.name
  description = "Nightly invoice settlement at 01:30 America/New_York (migrated from legacy cron)"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(30 1 * * ? *)"
  schedule_expression_timezone = "America/New_York"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.backup_scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.settlement.arn
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
        security_groups  = [aws_security_group.ecs.id]
        assign_public_ip = false
      }
    }
  }
}
