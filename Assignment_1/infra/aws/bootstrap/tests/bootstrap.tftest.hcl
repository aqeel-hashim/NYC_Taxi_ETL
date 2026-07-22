mock_provider "aws" {}
mock_provider "aws" { alias = "dr" }

run "state_is_regional_and_recoverable" {
  command = plan
  variables {
    bucket_prefix     = "nyc-taxi-123456789012"
    owner             = "data-platform"
    cost_center       = "platform"
    github_repository = "example/nyc-taxi-etl"
  }

  assert {
    condition     = aws_s3_bucket_versioning.primary.versioning_configuration[0].status == "Enabled"
    error_message = "Primary state bucket must be versioned."
  }

  assert {
    condition     = aws_s3_bucket_versioning.dr.versioning_configuration[0].status == "Enabled"
    error_message = "DR state bucket must be versioned."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.state.rule[0].status == "Enabled"
    error_message = "State replication must remain enabled."
  }

  assert {
    condition     = length(aws_iam_role.github) == 2
    error_message = "Bootstrap must create separate environment OIDC roles."
  }
}
