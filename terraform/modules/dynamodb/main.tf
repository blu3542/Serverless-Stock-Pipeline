resource "aws_dynamodb_table" "stock_movers" {
  name         = "${var.project_name}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # On-demand — stays in Free Tier

  hash_key = "date" # One winning stock per calendar day

  attribute {
    name = "date"
    type = "S" # "YYYY-MM-DD"
  }

  # Auto-expire records older than 90 days (belt-and-suspenders cost control)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-table-${var.environment}"
  }
}
