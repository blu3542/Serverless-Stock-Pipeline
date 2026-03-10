locals {
  builds_dir = "${path.module}/builds"
}

# ── Install pip dependencies into staging dirs before zipping ─────────────────
resource "null_resource" "ingestion_deps" {
  triggers = {
    requirements = filemd5("${path.root}/../lambda/ingestion/requirements.txt")
    handler      = filemd5("${path.root}/../lambda/ingestion/handler.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${local.builds_dir}/ingestion_pkg
      mkdir -p ${local.builds_dir}/ingestion_pkg
      pip3 install -r ${path.root}/../lambda/ingestion/requirements.txt -t ${local.builds_dir}/ingestion_pkg/ --quiet
      cp ${path.root}/../lambda/ingestion/handler.py ${local.builds_dir}/ingestion_pkg/
    EOT
  }
}

resource "null_resource" "retrieval_deps" {
  triggers = {
    requirements = filemd5("${path.root}/../lambda/retrieval/requirements.txt")
    handler      = filemd5("${path.root}/../lambda/retrieval/handler.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${local.builds_dir}/retrieval_pkg
      mkdir -p ${local.builds_dir}/retrieval_pkg
      pip3 install -r ${path.root}/../lambda/retrieval/requirements.txt -t ${local.builds_dir}/retrieval_pkg/ --quiet
      cp ${path.root}/../lambda/retrieval/handler.py ${local.builds_dir}/retrieval_pkg/
    EOT
  }
}

# ── Zip each staging dir ──────────────────────────────────────────────────────
data "archive_file" "ingestion" {
  depends_on  = [null_resource.ingestion_deps]
  type        = "zip"
  source_dir  = "${local.builds_dir}/ingestion_pkg"
  output_path = "${local.builds_dir}/ingestion.zip"
}

data "archive_file" "retrieval" {
  depends_on  = [null_resource.retrieval_deps]
  type        = "zip"
  source_dir  = "${local.builds_dir}/retrieval_pkg"
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
  timeout          = 300
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

# ── Analyst Lambda ────────────────────────────────────────────────────────────
resource "null_resource" "analyst_deps" {
  triggers = {
    requirements = filemd5("${path.root}/../lambda/analyst/requirements.txt")
    handler      = filemd5("${path.root}/../lambda/analyst/handler.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${local.builds_dir}/analyst_pkg
      mkdir -p ${local.builds_dir}/analyst_pkg
      pip3 install -r ${path.root}/../lambda/analyst/requirements.txt -t ${local.builds_dir}/analyst_pkg/ --quiet
      cp ${path.root}/../lambda/analyst/handler.py ${local.builds_dir}/analyst_pkg/
    EOT
  }
}

data "archive_file" "analyst" {
  depends_on  = [null_resource.analyst_deps]
  type        = "zip"
  source_dir  = "${local.builds_dir}/analyst_pkg"
  output_path = "${local.builds_dir}/analyst.zip"
}

resource "aws_lambda_function" "analyst" {
  function_name    = "${var.project_name}-analyst-${var.environment}"
  filename         = data.archive_file.analyst.output_path
  source_code_hash = data.archive_file.analyst.output_base64sha256
  role             = var.analyst_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE       = var.dynamodb_table_name
      ANTHROPIC_SECRET_ARN = var.anthropic_secret_arn
    }
  }

  tags = { Name = "${var.project_name}-analyst-${var.environment}" }
}

resource "aws_cloudwatch_log_group" "analyst" {
  name              = "/aws/lambda/${aws_lambda_function.analyst.function_name}"
  retention_in_days = 14
}
