terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}

resource "aws_prometheus_workspace" "this" {
  count = var.enabled ? 1 : 0
  alias = var.name
}

resource "aws_iam_role" "grafana" {
  count = var.enabled ? 1 : 0
  name  = "${var.name}-grafana"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "grafana" {
  count = var.enabled ? 1 : 0
  role  = aws_iam_role.grafana[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:ListWorkspaces", "aps:QueryMetrics", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata", "cloudwatch:GetMetricData", "cloudwatch:ListMetrics", "logs:StartQuery", "logs:GetQueryResults"]
      Resource = "*"
    }]
  })
}

resource "aws_grafana_workspace" "this" {
  count = var.enabled ? 1 : 0

  name                     = var.name
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["CLOUDWATCH", "PROMETHEUS"]
}

resource "aws_sns_topic" "alerts" {
  count             = var.enabled ? 1 : 0
  name              = "${var.name}-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = var.enabled ? toset(var.alert_emails) : toset([])
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sesv2_email_identity" "alerts" {
  count          = var.enabled ? 1 : 0
  email_identity = var.smtp_from_address
}

resource "aws_cloudwatch_metric_alarm" "global_lag" {
  count = var.enabled && var.database_cluster_id != null ? 1 : 0

  alarm_name          = "${var.name}-aurora-global-lag"
  alarm_description   = "Warn before the five-minute global database RPO objective"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 240000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  dimensions          = { DBClusterIdentifier = var.database_cluster_id }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
}

resource "aws_cloudwatch_log_group" "platform" {
  count             = var.enabled ? 1 : 0
  name              = "/${var.name}/platform"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.logs[0].arn
}

resource "aws_kms_key" "logs" {
  count                   = var.enabled ? 1 : 0
  description             = "${var.name} observability logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

variable "name" { type = string }
variable "enabled" { type = bool }
variable "alert_emails" { type = list(string) }
variable "smtp_from_address" { type = string }
variable "database_cluster_id" {
  type    = string
  default = null
}

output "enabled" { value = var.enabled }
output "prometheus_endpoint" { value = try(aws_prometheus_workspace.this[0].prometheus_endpoint, null) }
output "grafana_endpoint" { value = try(aws_grafana_workspace.this[0].endpoint, null) }
output "alert_topic_arn" { value = try(aws_sns_topic.alerts[0].arn, null) }
