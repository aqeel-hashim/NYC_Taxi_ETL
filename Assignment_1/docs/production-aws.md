# AWS Production Deployment

## Prerequisites

- AWS account with admin access
- GitHub repository with OIDC configured
- Cloudflare zone for DNS
- SMTP relay credentials (SES or external)

## Architecture

| Component | Dev | Prod |
|-----------|-----|------|
| Compute | EKS with Karpenter | EKS with Karpenter (Spot task nodes) |
| Database | Aurora Serverless v2 | Provisioned Aurora with Global Database |
| Object Storage | S3 (single region) | S3 with cross-region replication |
| Monitoring | In-cluster Prometheus/Grafana | Amazon Managed Prometheus + Grafana |
| DNS | Cloudflare DNS-only | Cloudflare proxied with WAF |

## Modules

| Module | Purpose |
|--------|---------|
| `vpc` | VPC, subnets, endpoints, egress |
| `eks` | EKS cluster, Karpenter, IRSA |
| `ecr` | Container registry, lifecycle, cross-region replication |
| `aurora` | PostgreSQL, RDS Proxy, Secrets Manager |
| `s3` | Source/checkpoint/quarantine/log buckets, lifecycle |
| `cognito` | User pools, identity pools, OIDC federation |
| `dns` | Cloudflare records, ACM certificates |
| `monitoring` | AMP workspace, AMG workspace, alert routes |
| `dr` | Warm standby in us-west-2, Aurora Global secondary |

## Deployment

```bash
cd Assignment_1/infra/aws
terraform init -backend-config=environments/dev/backend.tfvars
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

## Cost

Dev environment: target under $300/month.
Production: scaled based on data volume and query load.
Cost guard uses Infracost with 10% increase approval threshold.
