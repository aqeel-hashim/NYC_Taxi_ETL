terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.dr]
    }
  }
}

locals {
  callback_urls = ["https://${var.name}.invalid/oauth2/callback"]
}

resource "aws_cognito_user_pool" "primary" {
  name                = "${var.name}-primary"
  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  admin_create_user_config { allow_admin_create_user_only = true }
  password_policy {
    minimum_length                   = 16
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 1
  }
}

resource "aws_cognito_identity_provider" "primary" {
  user_pool_id  = aws_cognito_user_pool.primary.id
  provider_name = "EnterpriseOIDC"
  provider_type = "OIDC"
  provider_details = {
    authorize_scopes = join(" ", var.enterprise_oidc.scopes)
    client_id        = var.enterprise_oidc.client_id
    client_secret    = var.enterprise_oidc.client_secret
    oidc_issuer      = var.enterprise_oidc.issuer
  }
  attribute_mapping = { email = "email", username = "sub" }
}

resource "aws_cognito_user_pool_client" "primary" {
  name                                 = "${var.name}-web"
  user_pool_id                         = aws_cognito_user_pool.primary.id
  generate_secret                      = false
  supported_identity_providers         = [aws_cognito_identity_provider.primary.provider_name]
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  prevent_user_existence_errors        = "ENABLED"
}

resource "aws_cognito_user_pool" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr

  name                = "${var.name}-dr"
  deletion_protection = "ACTIVE"
  admin_create_user_config { allow_admin_create_user_only = true }
  password_policy {
    minimum_length                   = 16
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 1
  }
}

resource "aws_cognito_identity_provider" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr

  user_pool_id  = aws_cognito_user_pool.dr[0].id
  provider_name = "EnterpriseOIDC"
  provider_type = "OIDC"
  provider_details = {
    authorize_scopes = join(" ", var.enterprise_oidc.scopes)
    client_id        = var.enterprise_oidc.client_id
    client_secret    = var.enterprise_oidc.client_secret
    oidc_issuer      = var.enterprise_oidc.issuer
  }
  attribute_mapping = { email = "email", username = "sub" }
}

resource "aws_cognito_user_pool_client" "dr" {
  count    = var.enable_dr ? 1 : 0
  provider = aws.dr

  name                                 = "${var.name}-dr-web"
  user_pool_id                         = aws_cognito_user_pool.dr[0].id
  generate_secret                      = false
  supported_identity_providers         = [aws_cognito_identity_provider.dr[0].provider_name]
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  prevent_user_existence_errors        = "ENABLED"
}

variable "name" { type = string }
variable "enable_dr" { type = bool }
variable "deployment_role_arn" { type = string }
variable "deletion_protection" { type = bool }
variable "enterprise_oidc" {
  type      = object({ issuer = string, client_id = string, client_secret = string, scopes = list(string) })
  sensitive = true
}
variable "callback_urls" { type = list(string) }
variable "logout_urls" { type = list(string) }

output "deployment_role_arn" { value = var.deployment_role_arn }
output "primary_user_pool_id" { value = aws_cognito_user_pool.primary.id }
output "dr_enabled" { value = var.enable_dr }
output "dr_user_pool_id" { value = try(aws_cognito_user_pool.dr[0].id, null) }
