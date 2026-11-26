data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---- ECS Task Execution Role (<prefix>-<env>-task-execution) ----

resource "aws_iam_role" "task_execution" {
  name               = "${local.prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    Name = "${local.prefix}-task-execution"
  }
}

# ecr:GetAuthorizationToken does not support resource-level ARN scoping in AWS IAM; Resource="*" is forced by the ECR API.
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "task_execution" {
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
    resources = [
      "${aws_cloudwatch_log_group.api.arn}:*",
      "${aws_cloudwatch_log_group.worker.arn}:*",
      "${aws_cloudwatch_log_group.settlement.arn}:*",
    ]
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

resource "aws_iam_policy" "task_execution" {
  name   = "${local.prefix}-task-execution-policy"
  policy = data.aws_iam_policy_document.task_execution.json

  tags = {
    Name = "${local.prefix}-task-execution-policy"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.task_execution.arn
}

# ---- ECS Task Role (<prefix>-<env>-task) ----

resource "aws_iam_role" "task" {
  name               = "${local.prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    Name = "${local.prefix}-task"
  }
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "SqsOrdersQueue"
    effect    = "Allow"
    actions   = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.orders.arn]
  }

  statement {
    sid       = "S3ReceiptsBucket"
    effect    = "Allow"
    actions   = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.receipts.arn,
      "${aws_s3_bucket.receipts.arn}/*",
    ]
  }

  statement {
    sid       = "KmsForSqsAndS3"
    effect    = "Allow"
    actions   = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:Encrypt",
    ]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_policy" "task" {
  name   = "${local.prefix}-task-policy"
  policy = data.aws_iam_policy_document.task.json

  tags = {
    Name = "${local.prefix}-task-policy"
  }
}

resource "aws_iam_role_policy_attachment" "task" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task.arn
}
