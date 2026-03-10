output "secret_arn"           { value = aws_secretsmanager_secret.stock_api_key.arn }
output "secret_name"          { value = aws_secretsmanager_secret.stock_api_key.name }
output "anthropic_secret_arn" { value = aws_secretsmanager_secret.anthropic_api_key.arn }
