# ---- Immutable Backup S3 Bucket (Object Lock, name contains -backups-) ----

# S3 bucket names must contain -backups- for the shared nwo-backup-task role policy.
#trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "backups" {
  bucket              = "${local.prefix}-backups-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true
  force_destroy       = true

  tags = {
    Name = "${local.prefix}-backups"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "backups_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups_tls.json
}

# ---- Backup Log Group & Least-Privilege Execution / Scheduler Roles ----

resource "aws_cloudwatch_log_group" "backup" {
  name              = "${local.prefix}-backup"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name = "${local.prefix}-backup"
  }
}

resource "aws_iam_role" "backup_execution" {
  name               = "${local.prefix}-backup-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    Name = "${local.prefix}-backup-execution"
  }
}

# ecr:GetAuthorizationToken requires Resource="*" in AWS IAM.
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "backup_execution" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPull"
    effect    = "Allow"
    actions   = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.backup.arn}:*"]
  }

  statement {
    sid       = "ReadDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }

  statement {
    sid       = "DecryptDbSecretKms"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_policy" "backup_execution" {
  name   = "${local.prefix}-backup-execution-policy"
  policy = data.aws_iam_policy_document.backup_execution.json

  tags = {
    Name = "${local.prefix}-backup-execution-policy"
  }
}

resource "aws_iam_role_policy_attachment" "backup_execution" {
  role       = aws_iam_role.backup_execution.name
  policy_arn = aws_iam_policy.backup_execution.arn
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup_scheduler" {
  name               = "${local.prefix}-backup-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json

  tags = {
    Name = "${local.prefix}-backup-scheduler"
  }
}

data "aws_iam_policy_document" "backup_scheduler" {
  statement {
    sid       = "RunBackupTask"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = [
      aws_ecs_task_definition.backup.arn,
      aws_ecs_task_definition.settlement.arn,
    ]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.main.arn]
    }
  }

  statement {
    sid       = "PassBackupRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [
      aws_iam_role.backup_execution.arn,
      var.aws_backup_task_role_arn,
      aws_iam_role.task_execution.arn,
      aws_iam_role.task.arn,
    ]
  }
}

resource "aws_iam_policy" "backup_scheduler" {
  name   = "${local.prefix}-backup-scheduler-policy"
  policy = data.aws_iam_policy_document.backup_scheduler.json

  tags = {
    Name = "${local.prefix}-backup-scheduler-policy"
  }
}

resource "aws_iam_role_policy_attachment" "backup_scheduler" {
  role       = aws_iam_role.backup_scheduler.name
  policy_arn = aws_iam_policy.backup_scheduler.arn
}

# ---- Backup Fargate Task Definition (Shared nwo-backup-task role, <= 0.5 vCPU / 1 GB) ----

resource "aws_ecs_task_definition" "backup" {
  family                   = "${local.prefix}-backup"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.backup_execution.arn
  task_role_arn            = var.aws_backup_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "backup"
      image     = local.image
      essential = true
      command   = ["python", "-m", "app.dr_backup"]
      environment = [
        { name = "CLOUD", value = "aws" },
        { name = "SERVICE_NAME", value = "orders-backup" },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "AWS_BACKUP_BUCKET", value = aws_s3_bucket.backups.id },
        { name = "GCP_BACKUP_BUCKET", value = "${local.prefix}-backups-${var.gcp_project_id}" },
        { name = "GCP_AWS_WIF_PROVIDER", value = var.gcp_aws_wif_provider },
        { name = "GCP_BACKUP_WRITER_SERVICE_ACCOUNT", value = var.gcp_backup_writer_sa },
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
          "awslogs-group"         = aws_cloudwatch_log_group.backup.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backup"
        }
      }
    }
  ])

  tags = {
    Name = "${local.prefix}-backup"
  }
}

# ---- EventBridge Schedule (Every 10 minutes -> satisfies RPO <= 15m) ----

resource "aws_scheduler_schedule_group" "main" {
  name = "${local.prefix}-schedules"

  tags = {
    Name = "${local.prefix}-schedules"
  }
}

resource "aws_scheduler_schedule" "backup" {
  name        = "${local.prefix}-backup-10m"
  group_name  = aws_scheduler_schedule_group.main.name
  description = "Run DR backup task every 10 minutes (RPO <= 15m)"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(10 minutes)"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.backup_scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.backup.arn
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
