terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.dr]
    }
    cloudflare = { source = "cloudflare/cloudflare" }
  }
}

resource "aws_acm_certificate" "primary" {
  domain_name       = var.domain
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_acm_certificate" "dr" {
  count    = var.enable_failover ? 1 : 0
  provider = aws.dr

  domain_name       = var.domain
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "cloudflare_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.primary.domain_validation_options : option.domain_name => {
      name  = option.resource_record_name
      value = option.resource_record_value
      type  = option.resource_record_type
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  value           = each.value.value
  type            = each.value.type
  ttl             = 60
  proxied         = false
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "primary" {
  certificate_arn         = aws_acm_certificate.primary.arn
  validation_record_fqdns = [for record in cloudflare_record.validation : record.hostname]
}

resource "aws_acm_certificate_validation" "dr" {
  count    = var.enable_failover ? 1 : 0
  provider = aws.dr

  certificate_arn         = aws_acm_certificate.dr[0].arn
  validation_record_fqdns = [for record in cloudflare_record.validation : record.hostname]
}

resource "cloudflare_record" "direct" {
  count = var.enable_failover ? 0 : 1

  zone_id = var.zone_id
  name    = var.domain
  value   = var.primary_origin
  type    = "CNAME"
  ttl     = 60
  proxied = var.proxied
}

resource "cloudflare_load_balancer_monitor" "https" {
  count = var.enable_failover ? 1 : 0

  account_id       = var.cloudflare_account_id
  type             = "https"
  port             = 443
  method           = "GET"
  path             = "/healthz"
  expected_codes   = "200"
  interval         = 60
  timeout          = 5
  retries          = 2
  follow_redirects = false
  allow_insecure   = false
}

resource "cloudflare_load_balancer_pool" "primary" {
  count = var.enable_failover ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = replace("${var.domain}-primary", ".", "-")
  monitor    = cloudflare_load_balancer_monitor.https[0].id
  origins {
    name    = "primary"
    address = var.primary_origin
    enabled = true
  }
}

resource "cloudflare_load_balancer_pool" "dr" {
  count = var.enable_failover ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = replace("${var.domain}-dr", ".", "-")
  monitor    = cloudflare_load_balancer_monitor.https[0].id
  origins {
    name    = "dr"
    address = var.dr_origin
    enabled = true
  }
}

resource "cloudflare_load_balancer" "this" {
  count = var.enable_failover ? 1 : 0

  zone_id          = var.zone_id
  name             = var.domain
  fallback_pool_id = cloudflare_load_balancer_pool.dr[0].id
  default_pool_ids = [cloudflare_load_balancer_pool.primary[0].id, cloudflare_load_balancer_pool.dr[0].id]
  proxied          = true
  steering_policy  = "off"
}

resource "cloudflare_zone_settings_override" "security" {
  count   = var.proxied ? 1 : 0
  zone_id = var.zone_id
  settings {
    always_use_https = "on"
    min_tls_version  = "1.2"
    ssl              = "strict"
    tls_1_3          = "on"
    websockets       = "on"
  }
}

resource "cloudflare_ruleset" "waf" {
  count = var.proxied ? 1 : 0

  zone_id     = var.zone_id
  name        = "nyc-taxi-custom-waf"
  description = "Block high-confidence threats"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action      = "block"
    expression  = "(cf.threat_score gt 20)"
    description = "Block high threat score"
    enabled     = true
  }
}

resource "cloudflare_ruleset" "rate_limit" {
  count = var.proxied ? 1 : 0

  zone_id     = var.zone_id
  name        = "nyc-taxi-rate-limit"
  description = "Per-client request ceiling"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules {
    action      = "block"
    expression  = "true"
    description = "300 requests per minute per client"
    enabled     = true
    ratelimit {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 60
      requests_per_period = 300
      mitigation_timeout  = 60
    }
  }
}

variable "zone_id" { type = string }
variable "cloudflare_account_id" { type = string }
variable "domain" { type = string }
variable "primary_origin" { type = string }
variable "dr_origin" {
  type    = string
  default = null
}
variable "enable_failover" { type = bool }
variable "proxied" { type = bool }

output "primary_certificate_arn" { value = aws_acm_certificate_validation.primary.certificate_arn }
output "dr_certificate_arn" { value = try(aws_acm_certificate_validation.dr[0].certificate_arn, null) }
output "failover_enabled" { value = var.enable_failover }
