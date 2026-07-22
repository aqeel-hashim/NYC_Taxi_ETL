locals {
  name       = "${var.project}-${var.environment}"
  production = var.environment == "prod"
  az_count   = local.production ? 3 : 2
  tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "Terraform"
    ExpiresAt   = coalesce(var.expires_at, "never")
  }
}

module "primary_vpc" {
  source = "./modules/vpc"

  name            = "${local.name}-primary"
  cidr            = "10.20.0.0/16"
  az_count        = local.az_count
  one_nat_gateway = !local.production
}

module "dr_vpc" {
  count     = var.enable_dr ? 1 : 0
  source    = "./modules/vpc"
  providers = { aws = aws.dr }

  name            = "${local.name}-dr"
  cidr            = "10.30.0.0/16"
  az_count        = 3
  one_nat_gateway = true
}

module "primary_eks" {
  source = "./modules/eks"

  name                = "${local.name}-primary"
  vpc_id              = module.primary_vpc.vpc_id
  private_subnet_ids  = module.primary_vpc.private_subnet_ids
  system_desired_size = local.production ? 2 : 1
  system_min_size     = 1
  system_max_size     = local.production ? 4 : 2
  enable_karpenter    = true
}

module "dr_eks" {
  count     = var.enable_dr ? 1 : 0
  source    = "./modules/eks"
  providers = { aws = aws.dr }

  name                = "${local.name}-dr"
  vpc_id              = module.dr_vpc[0].vpc_id
  private_subnet_ids  = module.dr_vpc[0].private_subnet_ids
  system_desired_size = 1
  system_min_size     = 1
  system_max_size     = 2
  enable_karpenter    = true
}

module "ecr" {
  source = "./modules/ecr"

  name               = local.name
  repository_names   = ["airflow", "dashboard"]
  replication_region = var.dr_region
  registry_id         = var.aws_account_id
  enable_replication = var.enable_dr
  force_delete       = !local.production
}

module "object_storage" {
  source = "./modules/s3"
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  bucket_prefix = var.bucket_prefix
  dr_region     = var.dr_region
  enable_dr     = var.enable_dr
  force_destroy = !local.production
}

module "database" {
  source = "./modules/aurora"
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name                  = local.name
  vpc_id                = module.primary_vpc.vpc_id
  subnet_ids            = module.primary_vpc.database_subnet_ids
  eks_security_group    = module.primary_eks.node_security_group_id
  serverless            = !local.production
  enable_global         = var.enable_dr
  primary_region        = var.primary_region
  dr_region             = var.dr_region
  dr_vpc_id             = var.enable_dr ? module.dr_vpc[0].vpc_id : null
  dr_subnet_ids         = var.enable_dr ? module.dr_vpc[0].database_subnet_ids : []
  dr_eks_security_group = var.enable_dr ? module.dr_eks[0].node_security_group_id : null
}

module "airflow_proxy" {
  count  = local.production ? 1 : 0
  source = "./modules/rds-proxy"

  name                    = "${local.name}-airflow"
  vpc_id                  = module.primary_vpc.vpc_id
  subnet_ids              = module.primary_vpc.private_subnet_ids
  client_security_group   = module.primary_eks.node_security_group_id
  database_security_group = module.database.primary_security_group_id
  cluster_identifier      = module.database.primary_cluster_identifier
  secret_arn              = module.database.airflow_secret_arn
  kms_key_arn             = module.database.primary_kms_key_arn
}

module "warehouse_proxy" {
  count  = local.production ? 1 : 0
  source = "./modules/rds-proxy"

  name                    = "${local.name}-warehouse"
  vpc_id                  = module.primary_vpc.vpc_id
  subnet_ids              = module.primary_vpc.private_subnet_ids
  client_security_group   = module.primary_eks.node_security_group_id
  database_security_group = module.database.primary_security_group_id
  cluster_identifier      = module.database.primary_cluster_identifier
  secret_arn              = module.database.warehouse_secret_arn
  kms_key_arn             = module.database.primary_kms_key_arn
}

module "dr_airflow_proxy" {
  count     = var.enable_dr ? 1 : 0
  source    = "./modules/rds-proxy"
  providers = { aws = aws.dr }

  name                    = "${local.name}-dr-airflow"
  vpc_id                  = module.dr_vpc[0].vpc_id
  subnet_ids              = module.dr_vpc[0].private_subnet_ids
  client_security_group   = module.dr_eks[0].node_security_group_id
  database_security_group = module.database.dr_security_group_id
  cluster_identifier      = module.database.dr_cluster_identifier
  secret_arn              = module.database.dr_airflow_secret_arn
  kms_key_arn             = module.database.dr_kms_key_arn
}

module "dr_warehouse_proxy" {
  count     = var.enable_dr ? 1 : 0
  source    = "./modules/rds-proxy"
  providers = { aws = aws.dr }

  name                    = "${local.name}-dr-warehouse"
  vpc_id                  = module.dr_vpc[0].vpc_id
  subnet_ids              = module.dr_vpc[0].private_subnet_ids
  client_security_group   = module.dr_eks[0].node_security_group_id
  database_security_group = module.database.dr_security_group_id
  cluster_identifier      = module.database.dr_cluster_identifier
  secret_arn              = module.database.dr_warehouse_secret_arn
  kms_key_arn             = module.database.dr_kms_key_arn
}

module "identity" {
  source = "./modules/identity"
  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name                = local.name
  enable_dr           = var.enable_dr
  deployment_role_arn = var.deployment_role_arn
  deletion_protection = local.production
  enterprise_oidc     = var.enterprise_oidc
  callback_urls       = var.cognito_callback_urls
  logout_urls         = var.cognito_logout_urls
}

module "dns" {
  source = "./modules/dns"
  providers = {
    aws        = aws
    aws.dr     = aws.dr
    cloudflare = cloudflare
  }

  zone_id               = var.cloudflare_zone_id
  cloudflare_account_id = var.cloudflare_account_id
  domain                = var.app_domain
  primary_origin        = var.primary_origin
  dr_origin             = var.dr_origin
  enable_failover       = var.enable_dr
  proxied               = local.production
}

module "primary_observability" {
  source = "./modules/observability"

  name                = "${local.name}-primary"
  enabled             = local.production
  alert_emails        = var.budget_alert_emails
  smtp_from_address   = var.smtp_from_address
  database_cluster_id = null
}

module "dr_observability" {
  count     = var.enable_dr ? 1 : 0
  source    = "./modules/observability"
  providers = { aws = aws.dr }

  name                = "${local.name}-dr"
  enabled             = true
  alert_emails        = var.budget_alert_emails
  smtp_from_address   = var.smtp_from_address
  database_cluster_id = module.database.dr_cluster_identifier
}

module "budget" {
  source = "./modules/budget"

  name         = local.name
  limit_usd    = var.budget_usd
  alert_emails = var.budget_alert_emails
}

module "redshift" {
  source = "./modules/redshift"

  name       = local.name
  enabled    = var.enable_redshift
  subnet_ids = module.primary_vpc.private_subnet_ids
}
