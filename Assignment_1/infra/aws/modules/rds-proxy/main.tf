terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-proxy-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.client_security_group]
  }
}

resource "aws_vpc_security_group_ingress_rule" "database" {
  security_group_id            = var.database_security_group
  referenced_security_group_id = aws_security_group.this.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_iam_role" "this" {
  name = "${var.name}-proxy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "secret" {
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = var.secret_arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_db_proxy" "this" {
  name                   = var.name
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.this.arn
  vpc_security_group_ids = [aws_security_group.this.id]
  vpc_subnet_ids         = var.subnet_ids

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = var.secret_arn
    iam_auth    = "DISABLED"
  }
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name
  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 80
    max_idle_connections_percent = 40
  }
}

resource "aws_db_proxy_target" "this" {
  db_cluster_identifier = var.cluster_identifier
  db_proxy_name         = aws_db_proxy.this.name
  target_group_name     = aws_db_proxy_default_target_group.this.name
}

variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "client_security_group" { type = string }
variable "database_security_group" { type = string }
variable "cluster_identifier" { type = string }
variable "secret_arn" { type = string }
variable "kms_key_arn" { type = string }

output "endpoint" { value = aws_db_proxy.this.endpoint }
