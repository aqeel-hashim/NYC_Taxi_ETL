# AWS Terraform Operations

This stack is statically complete. It has not been deployed. Terraform tests prove topology and policy only; they do not prove the 99.9% availability, five-minute RPO, or one-hour RTO objectives.

## Manual prerequisites

1. Create a dedicated AWS account or approved workload account. Enable IAM Identity Center for AWS and Managed Grafana administrators.
2. Run `terraform -chdir=bootstrap init` and `terraform -chdir=bootstrap apply -var-file=terraform.tfvars`. Store the resulting local bootstrap state in the approved break-glass vault before migrating it to protected storage.
3. Review the bootstrap-created service-scoped dev/prod deployment policies and production permissions boundary against organization SCPs. The bootstrap GitHub OIDC provider is account-global.
4. Create GitHub environments named `assignment-1-{dev,prod}-{plan,apply,destroy,destroy-apply}`. Require one reviewer for apply, destroy-plan, and destroy-apply. Restrict deployment branches. Copy required variables/secrets into each environment because GitHub environment secrets are not shared.
5. Create a least-privilege Cloudflare token with Zone DNS, Zone Settings, Load Balancing, and Rulesets edit plus Zone read for one zone. Cloudflare Load Balancing and WAF/rate-limit entitlements must exist. Set Full (strict) TLS; Terraform also enforces it.
6. Register the application in the enterprise OIDC provider with both regional Cognito callback/logout URLs. Cognito-native passwords do not replicate; production uses the same external provider in each region.
7. Verify the SES identity or external SMTP route and confirm SNS email subscriptions.
8. Install Karpenter from its pinned Helm chart after EKS creation, using each cluster's `karpenter_role_arn` and interruption queue output. Apply an On-Demand system pool and Spot task pool with interruption handling and retry-safe Airflow tasks. Keep DR Airflow scheduler/API/triggerer replicas at zero until database promotion.
9. Initialize `airflow` and `taxi_warehouse` databases/users with the generated Secrets Manager values before attaching workloads. Do not use the cluster administrator from applications.
10. Configure regional ingress load balancers, ACM certificates, Kubernetes policies, backup jobs, Airflow/dashboard releases, AMP remote-write, and Cloudflare origins. DR releases remain installed but control-plane replicas remain zero.

Run `../../scripts/configure-cloud.sh --environment dev` after prerequisites. It validates AWS/Cloudflare, writes only ignored mode-0600 files, and never plans or applies.

Each protected GitHub environment needs `A1_DEPLOY_ROLE_ARN`, `A1_AWS_ACCOUNT_ID`, `A1_OWNER`, `A1_COST_CENTER`, `A1_BUDGET_USD`, `A1_ALERT_EMAILS`, `A1_CLOUDFLARE_ACCOUNT_ID`, `A1_CLOUDFLARE_ZONE_ID`, `A1_APP_DOMAIN`, `A1_PRIMARY_ORIGIN`, `A1_ENTERPRISE_OIDC_ISSUER`, `A1_ENTERPRISE_OIDC_CLIENT_ID`, `A1_SMTP_FROM_ADDRESS`, `A1_BACKEND_BUCKET`, `A1_BACKEND_KMS_KEY_ARN`, and `A1_BUCKET_PREFIX` variables. Dev also needs `A1_EXPIRES_AT`; prod needs `A1_DR_ORIGIN`. Plan/destroy environments need `A1_CLOUDFLARE_API_TOKEN` and `A1_ENTERPRISE_OIDC_CLIENT_SECRET`; plan also needs `INFRACOST_API_KEY`. Set `A1_INFRACOST_BASELINE_MONTHLY_USD` after the first approved estimate.

## Static verification

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
terraform -chdir=bootstrap init -backend=false
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap test
```

The protected workflow additionally runs TFLint, Checkov, Trivy configuration scanning, Infracost, and a reviewed saved plan. Dev is blocked above USD 300/month. Any increase above 10% needs an updated approved baseline.

## Publication contract

S3 replication is asynchronous and is not the five-minute critical publication control. Before marking a month published, the application must upload and verify checksums for `raw/`, `reference/`, `threshold/`, and `manifest/` objects in both regional buckets, then commit the publication manifest. Logs/checkpoints use S3 Replication Time Control and are excluded from the five-minute objective.

## Database promotion

1. Fence primary writes and pause schedules. Record the last committed warehouse audit ID and publication manifest in both regions.
2. Confirm Aurora global lag and object checksums. If `rds.global_db_rpo=300` stalls primary commits, preserve consistency; do not bypass the managed RPO setting.
3. Promote the Aurora global secondary. Update DR proxy secret host values, test both database users, run Airflow metadata checks/migrations, then start scheduler/API/triggerer and unpause schedules.
4. Enable the DR Cloudflare pool only after application/read-write health passes. Record measured data loss and elapsed recovery time.
5. Rebuild the former primary as a secondary before failback. Fence writes, repeat checks, promote, switch DNS, and record evidence.

Monthly restore, quarterly database failover, and annual regional disaster exercises are mandatory before objectives become evidence-backed claims.

## State recovery

1. Stop all workflows and verify no primary lock holder remains. Never copy a live `.tflock` into use.
2. Download the latest intact state object version from the DR bucket and verify its version ID, KMS access, serial, lineage, and backup copy.
3. Create a temporary `backend.hcl` pointing at the DR bucket/KMS key with a new lock object. Run `terraform init -reconfigure` and `terraform plan -refresh-only`; two reviewers must inspect unexpected drift.
4. Use `terraform force-unlock LOCK_ID` only after proving the owner is gone. Preserve lock/state versions for audit.
5. After primary recovery, copy the accepted state version back, verify replication, reconfigure the primary backend, and archive the incident evidence.

## Redshift threshold

Redshift Serverless is disabled. Enable it only after sustained volume or query SLA misses justify the cost, with `enable_redshift=true` and `redshift_confirmation=ENABLE_REDSHIFT`. First shard Parquet row groups; move transformation to Glue/EMR Spark above roughly 20 GiB/month or repeated 45-minute SLA misses.
