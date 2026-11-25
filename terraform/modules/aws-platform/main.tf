locals {
  prefix   = "${var.name_prefix}-${var.env}"
  alb_name = replace(substr("${local.prefix}-alb", 0, 32), "/-+$/", "")
  tg_name  = replace(substr("${local.prefix}-tg", 0, 32), "/-+$/", "")
  image    = var.image_digest != "" ? "${aws_ecr_repository.app.repository_url}@${var.image_digest}" : "${aws_ecr_repository.app.repository_url}:latest"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "shared" {
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-vpc"]
  }
}

data "aws_subnet" "public_1" {
  vpc_id = data.aws_vpc.shared.id
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-subnet-public1-us-east-1a"]
  }
}

data "aws_subnet" "public_2" {
  vpc_id = data.aws_vpc.shared.id
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-subnet-public2-us-east-1b"]
  }
}

data "aws_subnet" "private_1" {
  vpc_id = data.aws_vpc.shared.id
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-subnet-private1-us-east-1a"]
  }
}

data "aws_subnet" "private_2" {
  vpc_id = data.aws_vpc.shared.id
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-subnet-private2-us-east-1b"]
  }
}

data "aws_subnet" "data_1" {
  vpc_id = data.aws_vpc.shared.id
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-subnet-data1-us-east-1a"]
  }
}

data "aws_subnet" "data_2" {
  vpc_id = data.aws_vpc.shared.id
  filter {
    name   = "tag:Name"
    values = ["hu-devops-26-nov-subnet-data2-us-east-1b"]
  }
}
