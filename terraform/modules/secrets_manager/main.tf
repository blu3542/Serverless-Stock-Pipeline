resource "aws_secretsmanager_secret" "stock_api_key" {
  name                    = "${var.project_name}/${var.environment}/stock-api-key"
  description             = "Stock data provider API key for ${var.project_name} (${var.environment})"
  recovery_window_in_days = 0 # Allows immediate re-deploy during dev; set to 7 for prod hardening

  tags = {
    Name = "${var.project_name}-secret-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "stock_api_key" {
  secret_id = aws_secretsmanager_secret.stock_api_key.id
  secret_string = jsonencode({
    api_key = var.stock_api_key
  })
}

resource "aws_secretsmanager_secret" "anthropic_api_key" {
  name                    = "${var.project_name}/${var.environment}/anthropic-api-key"
  description             = "Anthropic API key for AI analyst feature"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-anthropic-secret-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "anthropic_api_key" {
  secret_id     = aws_secretsmanager_secret.anthropic_api_key.id
  secret_string = jsonencode({ api_key = var.anthropic_api_key })
}
