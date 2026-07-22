terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.dr]
    }
  }
}

locals {
  primary_name = "${var.bucket_prefix}-data"
  dr_name      = "${var.bucket_prefix}-data-dr"
  logs_name    = "${var.bucket_prefix}-access-logs"
}

resource "aws_kms_key" "primary" {
  description             = "S3 data encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_key" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr

  description             = "DR S3 data encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.logs_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

resource "aws_s3_bucket_acl" "logs" {
  bucket     = aws_s3_bucket.logs.id
  acl        = "log-delivery-write"
  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket" "primary" {
  bucket        = local.primary_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
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

resource "aws_s3_bucket_logging" "primary" {
  bucket        = aws_s3_bucket.primary.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "data/"
  depends_on    = [aws_s3_bucket_acl.logs]
}

resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "primary" {
  bucket = aws_s3_bucket.primary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.primary.arn, "${aws_s3_bucket.primary.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "raw-curated-seven-years"
    status = "Enabled"
    filter { prefix = "raw/" }
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
    expiration { days = 2557 }
    noncurrent_version_expiration { noncurrent_days = 90 }
  }

  rule {
    id     = "quarantine-ninety-days"
    status = "Enabled"
    filter { prefix = "quarantine/" }
    expiration { days = 90 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }

  rule {
    id     = "logs-ninety-days"
    status = "Enabled"
    filter { prefix = "logs/" }
    expiration { days = 90 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

resource "aws_s3_bucket" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr
  bucket   = local.dr_name
}

resource "aws_s3_bucket_versioning" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.dr[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.dr[0].id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.dr[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.dr[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "replication" {
  count = var.enable_dr ? 1 : 0
  name  = "${var.bucket_prefix}-replication"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_dr ? 1 : 0
  role  = aws_iam_role.replication[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersion", "s3:GetObjectVersionAcl", "s3:GetObjectVersionForReplication", "s3:GetObjectVersionTagging"]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateDelete", "s3:ReplicateObject", "s3:ReplicateTags"]
        Resource = "${aws_s3_bucket.dr[0].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [aws_kms_key.primary.arn, aws_kms_key.dr[0].arn]
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "primary" {
  count = var.enable_dr ? 1 : 0

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "all-data-to-dr"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.dr[0].arn
      storage_class = "STANDARD"
      encryption_configuration { replica_kms_key_id = aws_kms_key.dr[0].arn }
      metrics {
        status = "Enabled"
        event_threshold { minutes = 15 }
      }
      replication_time {
        status = "Enabled"
        time { minutes = 15 }
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects { status = "Enabled" }
    }

    delete_marker_replication { status = "Disabled" }
  }

  depends_on = [aws_s3_bucket_versioning.primary, aws_s3_bucket_versioning.dr]
}

variable "bucket_prefix" { type = string }
variable "dr_region" { type = string }
variable "enable_dr" { type = bool }
variable "force_destroy" { type = bool }

output "bucket_names" {
  value = {
    primary = aws_s3_bucket.primary.id
    dr      = try(aws_s3_bucket.dr[0].id, null)
    logs    = aws_s3_bucket.logs.id
  }
}
output "replication_enabled" { value = var.enable_dr }
output "critical_publication_prefixes" { value = ["raw/", "reference/", "threshold/", "manifest/"] }
