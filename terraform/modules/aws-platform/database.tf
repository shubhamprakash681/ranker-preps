resource "aws_db_subnet_group" "orders" {
  name        = "${local.prefix}-db-subnets"
  description = "Shared data subnets for ${local.prefix} RDS"
  subnet_ids  = [data.aws_subnet.data_1.id, data.aws_subnet.data_2.id]

  tags = {
    Name = "${local.prefix}-db-subnets"
  }
}

resource "aws_db_parameter_group" "pg16" {
  name        = "${local.prefix}-pg16"
  family      = "postgres16"
  description = "Enforce TLS in transit for ${local.prefix}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${local.prefix}-pg16"
  }
}

resource "aws_db_instance" "orders" {
  identifier     = "${local.prefix}-pg"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  multi_az            = true
  publicly_accessible = false

  db_name  = "orders"
  username = "orders"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.orders.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.pg16.name

  backup_retention_period   = 7
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.prefix}-pg-final"
  deletion_protection       = false

  tags = {
    Name = "${local.prefix}-pg"
  }
}
