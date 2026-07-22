resource "aws_redshiftserverless_namespace" "this" {
  count = var.enabled ? 1 : 0

  namespace_name        = var.name
  admin_username        = "redshift_admin"
  manage_admin_password = true
}

resource "aws_redshiftserverless_workgroup" "this" {
  count = var.enabled ? 1 : 0

  workgroup_name      = var.name
  namespace_name      = aws_redshiftserverless_namespace.this[0].namespace_name
  base_capacity       = 8
  publicly_accessible = false
  subnet_ids          = var.subnet_ids
}

variable "name" { type = string }
variable "enabled" {
  type    = bool
  default = false
}
variable "subnet_ids" { type = list(string) }

output "enabled" { value = var.enabled }
