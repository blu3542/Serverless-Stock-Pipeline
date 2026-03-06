variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix used in all resource names"
  type        = string
  default     = "stock-movers"
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "stock_api_key" {
  description = "API key for the stock data provider — never commit this value"
  type        = string
  sensitive   = true
}

variable "stock_watchlist" {
  description = "Ordered list of ticker symbols to monitor each day"
  type        = list(string)
  default     = ["AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "NVDA"]
}

variable "schedule_expression" {
  description = "EventBridge cron expression for the ingestion job. Default: 2 AM UTC (9 PM EST / 10 PM EDT), ~5 h after market close."
  type        = string
  default     = "cron(0 2 * * ? *)"
}
