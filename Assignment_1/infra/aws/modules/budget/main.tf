resource "aws_budgets_budget" "this" {
  name         = var.name
  budget_type  = "COST"
  limit_amount = tostring(var.limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = toset([50, 80, 100])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = var.alert_emails
    }
  }
}

variable "name" { type = string }
variable "limit_usd" {
  type = number
  validation {
    condition     = var.limit_usd > 0
    error_message = "limit_usd must be positive."
  }
}
variable "alert_emails" {
  type = list(string)
  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "At least one budget alert email is required."
  }
}

output "budget_name" { value = aws_budgets_budget.this.name }
