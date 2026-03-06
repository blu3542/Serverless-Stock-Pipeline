terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ── Storage ──────────────────────────────────────────────
module "dynamodb" {
  source       = "./modules/dynamodb"
  project_name = var.project_name
  environment  = var.environment
}

# ── Secrets ───────────────────────────────────────────────
module "secrets_manager" {
  source        = "./modules/secrets_manager"
  project_name  = var.project_name
  environment   = var.environment
  stock_api_key = var.stock_api_key
}

# ── IAM ───────────────────────────────────────────────────
module "iam" {
  source             = "./modules/iam"
  project_name       = var.project_name
  environment        = var.environment
  dynamodb_table_arn = module.dynamodb.table_arn
  secret_arn         = module.secrets_manager.secret_arn
}

# ── Lambda Functions ──────────────────────────────────────
module "lambda" {
  source              = "./modules/lambda"
  project_name        = var.project_name
  environment         = var.environment
  ingestion_role_arn  = module.iam.ingestion_lambda_role_arn
  retrieval_role_arn  = module.iam.retrieval_lambda_role_arn
  dynamodb_table_name = module.dynamodb.table_name
  secret_arn          = module.secrets_manager.secret_arn
  stock_watchlist     = var.stock_watchlist
}

# ── Scheduler ─────────────────────────────────────────────
module "eventbridge" {
  source                = "./modules/eventbridge"
  project_name          = var.project_name
  environment           = var.environment
  ingestion_lambda_arn  = module.lambda.ingestion_lambda_arn
  ingestion_lambda_name = module.lambda.ingestion_lambda_name
  schedule_expression   = var.schedule_expression
}

# ── API Layer ─────────────────────────────────────────────
module "api_gateway" {
  source                = "./modules/api_gateway"
  project_name          = var.project_name
  environment           = var.environment
  retrieval_lambda_arn  = module.lambda.retrieval_lambda_arn
  retrieval_lambda_name = module.lambda.retrieval_lambda_name
  aws_region            = var.aws_region
  aws_account_id        = data.aws_caller_identity.current.account_id
}

# ── Frontend Hosting ──────────────────────────────────────
module "s3" {
  source       = "./modules/s3"
  project_name = var.project_name
  environment  = var.environment
}
