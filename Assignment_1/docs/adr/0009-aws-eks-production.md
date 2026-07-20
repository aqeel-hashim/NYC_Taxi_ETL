# ADR-0009: AWS EKS as Production Target

## Status

Accepted.

## Context

The assignment's optional production design requires a cloud deployment target. The local platform uses kind with KubernetesExecutor; production should mirror this topology to minimize environment divergence.

## Decision

Target **Amazon EKS** with KubernetesExecutor for production Airflow, Aurora PostgreSQL for the warehouse, S3 for object storage, and Amazon Managed Prometheus/Grafana for observability.

- `us-east-1` primary, `us-west-2` disaster recovery.
- Karpenter for node autoscaling (On-Demand system nodes, Spot task nodes).
- Aurora Global Database for cross-region data replication.
- S3 cross-region replication for critical raw/reference/threshold objects.
- Cognito OIDC for application users; IAM Identity Center for administration.
- Cloudflare for DNS with Full (strict) TLS and WAF.

## Alternatives Considered

- **Amazon MWAA**: Managed Airflow but less control over executor, images, and pod configuration. Documented comparison but not deployed.
- **ECS/Fargate**: Different scheduling model; KubernetesExecutor is closer to local kind topology.
- **GCP/Azure**: Not analyzed. Single cloud to keep scope bounded.

## Consequences

- Terraform modules must cover VPC, EKS, ECR, Aurora, S3, Cognito, AMP/AMG, Cloudflare, and DR.
- Production availability objective: 99.9% monthly.
- RPO: 5 minutes (Aurora Global Database + synchronous dual-region S3 publication).
- RTO: 1 hour through warm DR capacity.
- Claims remain objectives until deployed failover/restore drills produce measured evidence.
- Redshift Serverless is an optional disabled module for future volume/SLA thresholds.
