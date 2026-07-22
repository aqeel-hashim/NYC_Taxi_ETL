terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.dr]
    }
    random = { source = "hashicorp/random" }
  }
}

locals {
  engine         = "aurora-postgresql"
  engine_version = "16.6"
}

resource "aws_kms_key" "primary" {
  description             = "${var.name} Aurora and secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_key" "dr" {
  count    = var.enable_global ? 1 : 0
  provider = aws.dr

  description             = "${var.name} DR Aurora and secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "random_password" "master" {
  length  = 40
  special = true
}

resource "random_password" "app" {
  for_each = toset(["airflow", "warehouse"])
  length   = 40
  special  = false
}

resource "aws_db_subnet_group" "primary" {
  name       = "${var.name}-primary"
  subnet_ids = var.subnet_ids
}

resource "aws_db_subnet_group" "dr" {
  count    = var.enable_global ? 1 : 0
  provider = aws.dr

  name       = "${var.name}-dr"
  subnet_ids = var.dr_subnet_ids
}

resource "aws_security_group" "primary" {
  name_prefix = "${var.name}-aurora-"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group]
  }
}

resource "aws_security_group" "dr" {
  count    = var.enable_global ? 1 : 0
  provider = aws.dr

  name_prefix = "${var.name}-dr-aurora-"
  vpc_id      = var.dr_vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.dr_eks_security_group]
  }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name   = "${var.name}-aurora-pg16"
  family = "aurora-postgresql16"

  dynamic "parameter" {
    for_each = var.enable_global ? [1] : []
    content {
      name         = "rds.global_db_rpo"
      value        = "300"
      apply_method = "pending-reboot"
    }
  }
}

resource "aws_rds_global_cluster" "this" {
  count = var.enable_global ? 1 : 0

  global_cluster_identifier = "${var.name}-global"
  engine                    = local.engine
  engine_version            = local.engine_version
  database_name             = "taxi_platform"
  storage_encrypted         = true
  deletion_protection       = true
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier              = "${var.name}-primary"
  engine                          = local.engine
  engine_version                  = local.engine_version
  database_name                   = "taxi_platform"
  master_username                 = "platform_admin"
  master_password                 = random_password.master.result
  global_cluster_identifier       = try(aws_rds_global_cluster.this[0].id, null)
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.primary.arn
  backup_retention_period         = var.enable_global ? 35 : 7
  preferred_backup_window         = "05:00-06:00"
  copy_tags_to_snapshot           = true
  deletion_protection             = var.enable_global
  skip_final_snapshot             = !var.enable_global
  final_snapshot_identifier       = var.enable_global ? "${var.name}-primary-final" : null
  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless ? [1] : []
    content {
      min_capacity = 0.5
      max_capacity = 4
    }
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.serverless ? 1 : 2

  identifier          = "${var.name}-primary-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.primary.id
  instance_class      = var.serverless ? "db.serverless" : "db.r6g.large"
  engine              = aws_rds_cluster.primary.engine
  engine_version      = aws_rds_cluster.primary.engine_version
  publicly_accessible = false
}

resource "aws_rds_cluster" "dr" {
  count    = var.enable_global ? 1 : 0
  provider = aws.dr

  cluster_identifier              = "${var.name}-dr"
  engine                          = local.engine
  engine_version                  = local.engine_version
  global_cluster_identifier       = aws_rds_global_cluster.this[0].id
  source_region                   = var.primary_region
  db_subnet_group_name            = aws_db_subnet_group.dr[0].name
  vpc_security_group_ids          = [aws_security_group.dr[0].id]
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.dr[0].arn
  backup_retention_period         = 35
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-dr-final"
  enabled_cloudwatch_logs_exports = ["postgresql"]
}

resource "aws_rds_cluster_instance" "dr" {
  count    = var.enable_global ? 1 : 0
  provider = aws.dr

  identifier          = "${var.name}-dr-1"
  cluster_identifier  = aws_rds_cluster.dr[0].id
  instance_class      = "db.r6g.large"
  engine              = aws_rds_cluster.dr[0].engine
  engine_version      = aws_rds_cluster.dr[0].engine_version
  publicly_accessible = false
}

resource "aws_secretsmanager_secret" "app" {
  for_each   = random_password.app
  name       = "${var.name}/${each.key}/database"
  kms_key_id = aws_kms_key.primary.arn

  dynamic "replica" {
    for_each = var.enable_global ? [1] : []
    content {
      region     = var.dr_region
      kms_key_id = aws_kms_key.dr[0].arn
    }
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each  = random_password.app
  secret_id = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode({
    username = each.key == "airflow" ? "airflow_metadata" : "taxi_warehouse"
    password = each.value.result
    engine   = "postgres"
    host     = aws_rds_cluster.primary.endpoint
    port     = 5432
    dbname   = each.key == "airflow" ? "airflow" : "taxi_warehouse"
  })
}

data "aws_secretsmanager_secret" "dr" {
  for_each   = var.enable_global ? random_password.app : {}
  provider   = aws.dr
  name       = aws_secretsmanager_secret.app[each.key].name
  depends_on = [aws_secretsmanager_secret_version.app]
}

variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "eks_security_group" { type = string }
variable "serverless" { type = bool }
variable "enable_global" { type = bool }
variable "dr_region" { type = string }
variable "primary_region" { type = string }
variable "dr_vpc_id" {
  type    = string
  default = null
}
variable "dr_subnet_ids" {
  type    = list(string)
  default = []
}
variable "dr_eks_security_group" {
  type    = string
  default = null
}

output "primary_cluster_identifier" { value = aws_rds_cluster.primary.id }
output "dr_cluster_identifier" { value = try(aws_rds_cluster.dr[0].id, null) }
output "global_cluster_identifier" { value = try(aws_rds_global_cluster.this[0].id, null) }
output "global_enabled" { value = var.enable_global }
output "primary_endpoint" { value = aws_rds_cluster.primary.endpoint }
output "dr_endpoint" { value = try(aws_rds_cluster.dr[0].reader_endpoint, null) }
output "airflow_secret_arn" { value = aws_secretsmanager_secret.app["airflow"].arn }
output "warehouse_secret_arn" { value = aws_secretsmanager_secret.app["warehouse"].arn }
output "dr_airflow_secret_arn" { value = try(data.aws_secretsmanager_secret.dr["airflow"].arn, null) }
output "dr_warehouse_secret_arn" { value = try(data.aws_secretsmanager_secret.dr["warehouse"].arn, null) }
output "primary_security_group_id" { value = aws_security_group.primary.id }
output "dr_security_group_id" { value = try(aws_security_group.dr[0].id, null) }
output "primary_kms_key_arn" { value = aws_kms_key.primary.arn }
output "dr_kms_key_arn" { value = try(aws_kms_key.dr[0].arn, null) }
