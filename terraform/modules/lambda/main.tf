locals {
  builds_dir = "${path.module}/builds"
}

# Zip Lambda source code from sibling /lambda directory
data "archive_file" "ingestion" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/ingestion"
  output_path = "${local.builds_dir}/ingestion.zip"
}

data "archive_file" "retrieval" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/retrieval"
  output_path = "${local.builds_dir}/retrieval.zip"
}

# ── Ingestion Lambda ──────────────────────────────────────────────────────────
resource "aws_lambda_function" "ingestion" {
  function_name    = "${var.project_name}-ingestion-${var.environment}"
  filename         = data.archive_file.ingestion.output_path
  source_code_hash = data.archive_file.ingestion.output_base64sha256
  role             = var.ingestion_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30  # Enough time for 6 sequential API calls with retries
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE  = var.dynamodb_table_name
      SECRET_ARN      = var.secret_arn
      STOCK_WATCHLIST = join(",", var.stock_watchlist)
    }
  }

  tags = { Name = "${var.project_name}-ingestion-${var.environment}" }
}

# ── Retrieval Lambda ──────────────────────────────────────────────────────────
resource "aws_lambda_function" "retrieval" {
  function_name    = "${var.project_name}-retrieval-${var.environment}"
  filename         = data.archive_file.retrieval.output_path
  source_code_hash = data.archive_file.retrieval.output_base64sha256
  role             = var.retrieval_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }

  tags = { Name = "${var.project_name}-retrieval-${var.environment}" }
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "ingestion" {
  name              = "/aws/lambda/${aws_lambda_function.ingestion.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "retrieval" {
  name              = "/aws/lambda/${aws_lambda_function.retrieval.function_name}"
  retention_in_days = 14
}
