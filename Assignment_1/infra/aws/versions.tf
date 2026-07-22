terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.100.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }

  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
