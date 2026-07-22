variable "project" {
  type    = string
  default = "nyc-taxi-etl"
}

variable "aws_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain 12 digits."
  }
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}

variable "owner" {
  type = string
}

variable "cost_center" {
  type = string
}

variable "expires_at" {
  type        = string
  default     = null
  description = "Required ISO-8601 date for dev."
  validation {
    condition     = var.expires_at == null || can(formatdate("YYYY-MM-DD", "${var.expires_at}T00:00:00Z"))
    error_message = "expires_at must be YYYY-MM-DD."
  }
}

variable "budget_usd" {
  type    = number
  default = 300
}

variable "budget_alert_emails" {
  type = list(string)
}

variable "bucket_prefix" {
  type        = string
  description = "Globally unique lowercase prefix, normally project-account-environment."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{8,45}[a-z0-9]$", var.bucket_prefix))
    error_message = "bucket_prefix must be 10-47 lowercase letters, digits, or hyphens."
  }
}

variable "deployment_role_arn" {
  type        = string
  description = "Environment-specific GitHub OIDC role created by bootstrap."
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudflare_account_id" {
  type = string
}

variable "app_domain" {
  type = string
}

variable "primary_origin" {
  type        = string
  description = "Primary ingress hostname without scheme."
}

variable "dr_origin" {
  type        = string
  default     = null
  description = "Warm DR ingress hostname without scheme."
}

variable "enterprise_oidc" {
  type = object({
    issuer        = string
    client_id     = string
    client_secret = string
    scopes        = list(string)
  })
  sensitive = true
}

variable "cognito_callback_urls" {
  type = list(string)
}

variable "cognito_logout_urls" {
  type = list(string)
}

variable "smtp_from_address" {
  type = string
}

variable "enable_dr" {
  type    = bool
  default = false
}

variable "enable_redshift" {
  type    = bool
  default = false
}

variable "prod_confirmation" {
  type      = string
  default   = ""
  sensitive = true
}

variable "dr_confirmation" {
  type      = string
  default   = ""
  sensitive = true
}

variable "redshift_confirmation" {
  type      = string
  default   = ""
  sensitive = true
}

variable "publication_confirmation" {
  type      = string
  default   = ""
  sensitive = true
}

variable "speculative" {
  type        = bool
  default     = false
  description = "Disables provider account checks only for credential-free tests/plans."
}
