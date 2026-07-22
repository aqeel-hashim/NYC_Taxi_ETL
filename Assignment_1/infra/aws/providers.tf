provider "aws" {
  region = var.primary_region

  skip_credentials_validation = var.speculative
  skip_metadata_api_check     = var.speculative
  skip_region_validation      = var.speculative
  skip_requesting_account_id  = var.speculative

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  skip_credentials_validation = var.speculative
  skip_metadata_api_check     = var.speculative
  skip_region_validation      = var.speculative
  skip_requesting_account_id  = var.speculative

  default_tags {
    tags = local.tags
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
