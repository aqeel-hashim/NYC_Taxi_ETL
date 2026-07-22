locals {
  primary_bucket = "${var.bucket_prefix}-state-primary"
  dr_bucket      = "${var.bucket_prefix}-state-dr"
  tags = {
    Project     = "nyc-taxi-etl"
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
    Criticality = "state"
  }
}

resource "aws_kms_key" "primary" {
  description             = "Terraform state primary"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}

resource "aws_kms_key" "dr" {
  provider                = aws.dr
  description             = "Terraform state DR"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket" "primary" {
  bucket = local.primary_bucket
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket" "dr" {
  provider = aws.dr
  bucket   = local.dr_bucket
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.primary.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.dr.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each                = { primary = aws_s3_bucket.primary.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "dr" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "replication" {
  name = "${var.bucket_prefix}-state-replication"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "s3.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetReplicationConfiguration", "s3:ListBucket"], Resource = aws_s3_bucket.primary.arn },
      { Effect = "Allow", Action = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"], Resource = "${aws_s3_bucket.primary.arn}/*" },
      { Effect = "Allow", Action = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"], Resource = "${aws_s3_bucket.dr.arn}/*" },
      { Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = [aws_kms_key.primary.arn, aws_kms_key.dr.arn] }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "state" {
  bucket = aws_s3_bucket.primary.id
  role   = aws_iam_role.replication.arn
  rule {
    id     = "state-to-dr"
    status = "Enabled"
    destination {
      bucket = aws_s3_bucket.dr.arn
      encryption_configuration { replica_kms_key_id = aws_kms_key.dr.arn }
    }
    source_selection_criteria {
      sse_kms_encrypted_objects { status = "Enabled" }
    }
    delete_marker_replication { status = "Disabled" }
  }
  depends_on = [aws_s3_bucket_versioning.primary, aws_s3_bucket_versioning.dr]
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  deploy_actions = [
    "acm:*",
    "aps:*",
    "budgets:*",
    "cloudwatch:*",
    "cognito-idp:*",
    "ec2:*",
    "ecr:*",
    "eks:*",
    "grafana:*",
    "iam:AttachRolePolicy",
    "iam:CreateInstanceProfile",
    "iam:CreateRole",
    "iam:CreateServiceLinkedRole",
    "iam:DeleteInstanceProfile",
    "iam:DeleteRole",
    "iam:DeleteRolePolicy",
    "iam:DetachRolePolicy",
    "iam:GetInstanceProfile",
    "iam:GetRole",
    "iam:GetRolePolicy",
    "iam:ListAttachedRolePolicies",
    "iam:ListInstanceProfilesForRole",
    "iam:ListRolePolicies",
    "iam:PassRole",
    "iam:PutRolePolicy",
    "iam:RemoveRoleFromInstanceProfile",
    "iam:AddRoleToInstanceProfile",
    "iam:TagRole",
    "iam:UntagRole",
    "kms:*",
    "logs:*",
    "pricing:GetProducts",
    "rds:*",
    "redshift-serverless:*",
    "s3:*",
    "secretsmanager:*",
    "sns:*",
    "sqs:*",
    "ssm:GetParameter",
    "sts:GetCallerIdentity",
  ]
}

resource "aws_iam_policy" "github" {
  for_each = toset(["dev", "prod"])
  name     = "nyc-taxi-${each.key}-terraform"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ProjectTerraformServices"
      Effect   = "Allow"
      Action   = local.deploy_actions
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "prod_boundary" {
  name = "nyc-taxi-prod-boundary"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ProjectTerraformBoundary"
      Effect   = "Allow"
      Action   = local.deploy_actions
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "github" {
  for_each = {
    dev = {
      permissions_boundary = null
    }
    prod = {
      permissions_boundary = aws_iam_policy.prod_boundary.arn
    }
  }

  name                 = "nyc-taxi-${each.key}-github-deploy"
  permissions_boundary = each.value.permissions_boundary
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            for stage in ["plan", "apply", "destroy", "destroy-apply"] : "repo:${var.github_repository}:environment:assignment-1-${each.key}-${stage}"
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "github" {
  for_each   = aws_iam_role.github
  role       = each.value.name
  policy_arn = aws_iam_policy.github[each.key].arn
}

variable "bucket_prefix" { type = string }
variable "owner" { type = string }
variable "cost_center" { type = string }
variable "github_repository" { type = string }
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "dr_region" {
  type    = string
  default = "us-west-2"
}

output "primary_bucket" { value = aws_s3_bucket.primary.id }
output "dr_bucket" { value = aws_s3_bucket.dr.id }
output "primary_kms_key_arn" { value = aws_kms_key.primary.arn }
output "dr_kms_key_arn" { value = aws_kms_key.dr.arn }
output "github_oidc_provider_arn" { value = aws_iam_openid_connect_provider.github.arn }
output "github_deployment_role_arns" { value = { for environment, role in aws_iam_role.github : environment => role.arn } }
