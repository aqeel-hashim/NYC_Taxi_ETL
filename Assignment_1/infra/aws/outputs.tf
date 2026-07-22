output "deployment_role_arn" {
  value = module.identity.deployment_role_arn
}

output "eks_clusters" {
  value = compact([module.primary_eks.cluster_name, var.enable_dr ? module.dr_eks[0].cluster_name : null])
}

output "database_endpoints" {
  sensitive = true
  value = {
    primary = module.database.primary_endpoint
    dr      = module.database.dr_endpoint
  }
}

output "object_buckets" {
  value = module.object_storage.bucket_names
}

output "static_assertions" {
  description = "Topology/policy evidence only; this does not prove availability, RPO, or RTO."
  value = {
    warm_dr                      = var.enable_dr && length(module.dr_eks) == 1
    aurora_global                = module.database.global_enabled
    regional_proxies             = var.enable_dr && length(module.dr_airflow_proxy) == 1 && length(module.dr_warehouse_proxy) == 1
    s3_replication               = module.object_storage.replication_enabled
    ecr_replication              = module.ecr.replication_enabled
    regional_identity            = module.identity.dr_enabled
    regional_monitoring          = var.enable_dr && length(module.dr_observability) == 1
    dns_failover                 = module.dns.failover_enabled
    synchronous_publish_policy   = nonsensitive(var.publication_confirmation == "DUAL_REGION_PUBLISH")
    state_recovery_documented    = true
    redshift_disabled_by_default = !var.enable_redshift
  }
}
