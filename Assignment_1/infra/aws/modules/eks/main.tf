terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}

resource "aws_kms_key" "eks" {
  description             = "${var.name} Kubernetes secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 90
}

resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_security_group" "cluster" {
  name_prefix = "${var.name}-cluster-"
  vpc_id      = var.vpc_id
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  encryption_config {
    provider { key_arn = aws_kms_key.eks.arn }
    resources = ["secrets"]
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  depends_on = [aws_cloudwatch_log_group.cluster, aws_iam_role_policy_attachment.cluster]
}

resource "aws_iam_role" "node" {
  name = "${var.name}-system-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["m6i.large"]
  capacity_type   = "ON_DEMAND"

  labels = { workload = "system" }
  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  scaling_config {
    desired_size = var.system_desired_size
    min_size     = var.system_min_size
    max_size     = var.system_max_size
  }

  update_config { max_unavailable = 1 }
  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle { ignore_changes = [scaling_config[0].desired_size] }
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_sqs_queue" "karpenter" {
  count                     = var.enable_karpenter ? 1 : 0
  name                      = "${var.name}-karpenter-interruption"
  kms_master_key_id         = "alias/aws/sqs"
  message_retention_seconds = 300
}

resource "aws_iam_role" "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  name  = "${var.name}-karpenter-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  name  = "controller"
  role  = aws_iam_role.karpenter[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateFleet", "ec2:CreateLaunchTemplate", "ec2:CreateTags", "ec2:DeleteLaunchTemplate", "ec2:Describe*", "ec2:RunInstances", "pricing:GetProducts", "ssm:GetParameter"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.karpenter[0].arn
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.node.arn
      },
      {
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = aws_eks_cluster.this.arn
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "karpenter" {
  count           = var.enable_karpenter ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter[0].arn
}

variable "name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "kubernetes_version" {
  type    = string
  default = "1.32"
}
variable "system_desired_size" { type = number }
variable "system_min_size" { type = number }
variable "system_max_size" { type = number }
variable "enable_karpenter" {
  type    = bool
  default = true
}

output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "node_security_group_id" { value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }
output "karpenter_role_arn" { value = try(aws_iam_role.karpenter[0].arn, null) }
output "karpenter_queue_name" { value = try(aws_sqs_queue.karpenter[0].name, null) }
