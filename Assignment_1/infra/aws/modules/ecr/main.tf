resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain 50 release images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 50
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0
  replication_configuration {
    rule {
      destination {
        region      = var.replication_region
        registry_id = var.registry_id
      }
      repository_filter {
        filter      = "${var.name}/"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

variable "name" { type = string }
variable "repository_names" { type = list(string) }
variable "replication_region" { type = string }
variable "registry_id" { type = string }
variable "enable_replication" { type = bool }
variable "force_delete" { type = bool }

output "repository_urls" { value = { for key, repo in aws_ecr_repository.this : key => repo.repository_url } }
output "replication_enabled" { value = var.enable_replication }
