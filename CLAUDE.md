# AGENTS.md — Stock Movers Dashboard

## Project Overview

Serverless AWS stock tracking dashboard. Monitors 6 tech stocks daily,
identifies the largest mover by absolute % change, stores history, and
displays it on a public frontend with an AI Analyst chat feature.

## Watchlist

AAPL, MSFT, GOOGL, AMZN, TSLA, NVDA

## Repository Structure

```
stock-movers/
├── .github/workflows/deploy.yml   # CI/CD — GitHub Actions
├── terraform/
│   ├── main.tf                    # Root — wires all modules
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── dynamodb/
│       ├── secrets_manager/       # Holds Massive API key + Anthropic API key
│       ├── iam/
│       ├── lambda/
│       ├── eventbridge/
│       ├── api_gateway/
│       └── s3/
├── lambda/
│   ├── ingestion/handler.py       # Triggered nightly, writes to DynamoDB
│   ├── retrieval/handler.py       # GET /movers — reads from DynamoDB
│   └── analyst/handler.py         # POST /analyst — proxies to Anthropic API
└── frontend/index.html            # Single file SPA, hosted on S3
```

## Tech Stack

- **IaC:** Terraform >= 1.5, fully modularized (no manual console clicks)
- **Runtime:** Python 3.12
- **Scheduler:** EventBridge cron — `cron(0 21 * * ? *)` (after market close EST)
- **Compute:** AWS Lambda x3 (ingestion, retrieval, analyst)
- **Database:** DynamoDB (On-Demand mode)
- **API:** API Gateway REST — two routes: GET /movers, POST /analyst
- **Secrets:** AWS Secrets Manager (Massive API key + Anthropic API key)
- **Frontend:** S3 static website hosting
- **Stock Data:** Massive API
- **CI/CD:** GitHub Actions → terraform apply on push to main

## Lambda Responsibilities

### ingestion/handler.py

- Fetches daily open/close for all 6 tickers from Massive API
- Finds the ticker with highest absolute % change (the day's "winner")
- Fetches 90 days of historical data for the winner
- Computes z-score: `(today_pct - mean) / std_dev` over 90-day window
- Flags `is_significant = True` if `abs(z_score) > 2.0`
- Writes one record to DynamoDB per day

### retrieval/handler.py

- Returns last N days of DynamoDB records (default 7, max 30)
- Fields: date, ticker, pct_change, open, close, z_score, is_significant

### analyst/handler.py

- Receives `{ "question": string, "context_days": int }` from frontend
- Fetches last N days from DynamoDB as context
- Retrieves Anthropic API key from Secrets Manager
- Calls Anthropic API with web_search tool enabled (claude-sonnet-4-6)
- Returns natural language answer about stock movements and news

## API Gateway Routes

- `GET /movers` → retrieval Lambda
- `POST /analyst` → analyst Lambda
- Both routes have CORS enabled (`Access-Control-Allow-Origin: *`)

## DynamoDB Schema

Table name passed via `DYNAMODB_TABLE` env var to each Lambda.
Primary key: `date` (string, YYYY-MM-DD format)
Fields: ticker, pct_change, open_price, close_price, z_score, is_significant

## Secrets Manager

- Secret 1: Massive API key → env var `SECRET_ARN` in ingestion Lambda
- Secret 2: Anthropic API key → env var `ANTHROPIC_SECRET_ARN` in analyst Lambda

## Environment Variables (per Lambda)

All injected via Terraform, never hardcoded.

- `DYNAMODB_TABLE` — shared across all three Lambdas
- `SECRET_ARN` — ingestion only
- `ANTHROPIC_SECRET_ARN` — analyst only

## Important Rules

- Never hardcode API keys or ARNs — always read from Secrets Manager at runtime
- Never manually click in AWS Console — all infra changes go through Terraform
- Do not modify `terraform.tfvars` — use `terraform.tfvars.example` as reference
- Redeploying API Gateway requires a new `aws_api_gateway_deployment` — the
  existing triggers hash should detect changes automatically, but verify after apply
- Lambda timeout for analyst is 30s (Anthropic web search can be slow)

## Build & Run Commands

```bash
# Deploy all infrastructure
cd terraform && terraform init && terraform apply

# Test ingestion Lambda locally
cd lambda/ingestion && pip install -r requirements.txt
# (requires AWS credentials + env vars set)

# Test retrieval endpoint
curl https://<api-gateway-url>/movers

# Test analyst endpoint
curl -X POST https://<api-gateway-url>/analyst \
  -H "Content-Type: application/json" \
  -d '{"question": "Why did NVDA move today?", "context_days": 7}'
```

## CI/CD

GitHub Actions workflow in `.github/workflows/deploy.yml`
Runs `terraform apply` on push to main.
Secrets stored as GitHub repository secrets:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `TF_VAR_ANTHROPIC_API_KEY`
