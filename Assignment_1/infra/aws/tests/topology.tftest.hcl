mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-west-2a", "us-west-2b", "us-west-2c"]
    }
  }
  mock_data "aws_region" {
    defaults = { name = "us-west-2" }
  }
}

mock_provider "cloudflare" {}
mock_provider "random" {}

run "dev_is_low_cost_and_single_region" {
  command = plan

  variables {
    environment           = "dev"
    aws_account_id        = "123456789012"
    owner                 = "data-platform"
    cost_center           = "demo"
    expires_at            = "2099-01-01"
    budget_usd            = 300
    budget_alert_emails   = ["owner@example.com"]
    bucket_prefix         = "nyc-taxi-123456789012-dev"
    deployment_role_arn   = "arn:aws:iam::123456789012:role/nyc-taxi-dev-deploy"
    cloudflare_api_token  = "test-token"
    cloudflare_account_id = "0123456789abcdef0123456789abcdef"
    cloudflare_zone_id    = "0123456789abcdef0123456789abcdef"
    app_domain            = "dev.taxi.example.com"
    primary_origin        = "dev-origin.example.com"
    enterprise_oidc       = { issuer = "https://identity.example.com", client_id = "taxi", client_secret = "test", scopes = ["openid", "email", "profile"] }
    cognito_callback_urls = ["https://dev.taxi.example.com/oauth2/callback"]
    cognito_logout_urls   = ["https://dev.taxi.example.com/"]
    smtp_from_address     = "alerts@example.com"
    enable_dr             = false
    speculative           = true
  }

  assert {
    condition     = output.static_assertions.warm_dr == false
    error_message = "Dev must not provision warm DR."
  }

  assert {
    condition     = output.static_assertions.redshift_disabled_by_default
    error_message = "Redshift must remain disabled by default."
  }
}

run "prod_has_guarded_warm_dr" {
  command = plan

  variables {
    environment              = "prod"
    aws_account_id           = "123456789012"
    owner                    = "data-platform"
    cost_center              = "production"
    budget_usd               = 2500
    budget_alert_emails      = ["owner@example.com"]
    bucket_prefix            = "nyc-taxi-123456789012-prod"
    deployment_role_arn      = "arn:aws:iam::123456789012:role/nyc-taxi-prod-deploy"
    cloudflare_api_token     = "test-token"
    cloudflare_account_id    = "0123456789abcdef0123456789abcdef"
    cloudflare_zone_id       = "0123456789abcdef0123456789abcdef"
    app_domain               = "taxi.example.com"
    primary_origin           = "primary.example.com"
    dr_origin                = "dr.example.com"
    enterprise_oidc          = { issuer = "https://identity.example.com", client_id = "taxi", client_secret = "test", scopes = ["openid", "email", "profile"] }
    cognito_callback_urls    = ["https://taxi.example.com/oauth2/callback"]
    cognito_logout_urls      = ["https://taxi.example.com/"]
    smtp_from_address        = "alerts@example.com"
    enable_dr                = true
    prod_confirmation        = "DEPLOY_PRODUCTION"
    dr_confirmation          = "WARM_DR_READY"
    publication_confirmation = "DUAL_REGION_PUBLISH"
    speculative              = true
  }

  assert {
    condition = alltrue([
      output.static_assertions.warm_dr,
      output.static_assertions.aurora_global,
      output.static_assertions.regional_proxies,
      output.static_assertions.s3_replication,
      output.static_assertions.ecr_replication,
      output.static_assertions.regional_identity,
      output.static_assertions.regional_monitoring,
      output.static_assertions.dns_failover,
      output.static_assertions.synchronous_publish_policy,
      output.static_assertions.state_recovery_documented,
    ])
    error_message = "Production static topology must include every warm-DR policy component."
  }
}
