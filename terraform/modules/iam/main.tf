locals {
  lambda_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# ── Ingestion Lambda Role ─────────────────────────────────────────────────────
# Permissions: DynamoDB write + Secrets Manager read + CloudWatch logs

resource "aws_iam_role" "ingestion_lambda" {
  name               = "${var.project_name}-ingestion-${var.environment}"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "ingestion_lambda" {
  name = "${var.project_name}-ingestion-policy-${var.environment}"
  role = aws_iam_role.ingestion_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBWrite"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = var.dynamodb_table_arn
      },
      {
        Sid    = "ReadApiKey"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = var.secret_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Retrieval Lambda Role ─────────────────────────────────────────────────────
# Permissions: DynamoDB read-only + CloudWatch logs (no Secrets access needed)

resource "aws_iam_role" "retrieval_lambda" {
  name               = "${var.project_name}-retrieval-${var.environment}"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "retrieval_lambda" {
  name = "${var.project_name}-retrieval-policy-${var.environment}"
  role = aws_iam_role.retrieval_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = var.dynamodb_table_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
