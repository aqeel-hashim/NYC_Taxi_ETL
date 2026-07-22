resource "terraform_data" "guards" {
  input = var.environment

  lifecycle {
    precondition {
      condition     = var.primary_region == "us-east-1" && var.dr_region == "us-west-2"
      error_message = "ADR-0009 fixes primary to us-east-1 and DR to us-west-2."
    }

    precondition {
      condition     = var.environment != "dev" || (var.expires_at != null && var.budget_usd <= 300)
      error_message = "Dev requires expires_at and a monthly budget no greater than USD 300."
    }

    precondition {
      condition     = var.environment != "prod" || var.prod_confirmation == "DEPLOY_PRODUCTION"
      error_message = "Production requires prod_confirmation=DEPLOY_PRODUCTION."
    }

    precondition {
      condition = var.environment != "prod" || (
        var.enable_dr && var.dr_confirmation == "WARM_DR_READY" && var.dr_origin != null
      )
      error_message = "Production requires confirmed warm DR and a DR ingress origin."
    }

    precondition {
      condition     = var.environment != "prod" || var.publication_confirmation == "DUAL_REGION_PUBLISH"
      error_message = "Production must confirm application-level synchronous dual-region publication."
    }

    precondition {
      condition     = !var.enable_redshift || var.redshift_confirmation == "ENABLE_REDSHIFT"
      error_message = "Redshift is disabled unless separately confirmed."
    }
  }
}
