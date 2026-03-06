# Stock Movers

A fully automated, serverless AWS pipeline that tracks a watchlist of 6 tech stocks daily, identifies the single largest mover by absolute % change, and surfaces the results on a public frontend — with a statistical significance layer (z-score) that flags genuinely unusual moves.

---

## Architecture

```
                           ┌─────────────────────────────────────────────────┐
                           │                    AWS (us-east-1)               │
                           │                                                   │
  Market close (5 PM EST)  │  ┌──────────────┐    ┌─────────────────────┐    │
  ─────────────────────────┼─▶│  EventBridge │───▶│  Lambda: Ingestion  │    │
  cron(0 21 * * ? *)       │  └──────────────┘    │  (Python 3.12)      │    │
                           │                       │                     │    │
                           │  ┌────────────────┐   │  1. Fetch OHLC for  │    │
                           │  │ Secrets Manager│◀──│     6 tickers       │    │
                           │  │ (API key)      │   │  2. Find winner     │    │
                           │  └────────────────┘   │  3. Compute z-score │    │
                           │                       │  4. Write to DB     │    │
                           │                       └──────────┬──────────┘    │
                           │                                  │               │
                           │                       ┌──────────▼──────────┐    │
                           │                       │     DynamoDB        │    │
                           │                       │  (one row / day)    │    │
                           │                       └──────────┬──────────┘    │
                           │                                  │               │
                           │  ┌──────────────┐   ┌───────────▼─────────┐     │
  Browser ─────────────────┼─▶│ API Gateway  │──▶│  Lambda: Retrieval  │     │
  GET /movers              │  │ REST API     │   │  (Python 3.12)      │     │
                           │  └──────────────┘   │  Last 7 days, JSON  │     │
                           │                      └─────────────────────┘     │
                           │                                                   │
  Browser ─────────────────┼─▶  S3 Static Website  (index.html)               │
                           └─────────────────────────────────────────────────┘
```

**Stock Watchlist:** `AAPL · MSFT · GOOGL · AMZN · TSLA · NVDA`

---

## Prerequisites

| Tool | Version |
|---|---|
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2+ |
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5 |
| [Python](https://www.python.org/downloads/) | 3.12 (for local Lambda testing only) |

You also need a [Massive API](https://massive.com) key for stock data.

---

## First-Time Setup

### 1. Configure AWS credentials

```bash
aws configure
# AWS Access Key ID:     <your key>
# AWS Secret Access Key: <your secret>
# Default region:        us-east-1
# Default output format: json
```

### 2. Copy and fill in the Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set your Massive API key:

```hcl
stock_api_key = "your_actual_api_key_here"
```

> `terraform.tfvars` is in `.gitignore` — it will never be committed.

---

## Deploy

```bash
cd terraform

# Download providers
terraform init

# Preview changes
terraform plan

# Deploy everything
terraform apply
```

After apply, Terraform prints four outputs:

```
api_endpoint        = "https://xxxx.execute-api.us-east-1.amazonaws.com/prod/movers"
frontend_url        = "http://stock-movers-frontend-prod-abcd1234.s3-website-us-east-1.amazonaws.com"
dynamodb_table_name = "stock-movers-prod"
s3_bucket_name      = "stock-movers-frontend-prod-abcd1234"
```

### 3. Wire the frontend to the API

Edit `frontend/index.html` and replace the placeholder at the top of the `<script>` block:

```js
const API_URL = "https://xxxx.execute-api.us-east-1.amazonaws.com/prod/movers";
```

### 4. Deploy the frontend

```bash
BUCKET=$(cd terraform && terraform output -raw s3_bucket_name)
aws s3 sync ./frontend s3://$BUCKET --delete
```

Open the `frontend_url` output in a browser — you should see the dashboard.

---

## CI/CD (GitHub Actions)

Every push to `main` automatically runs the full deploy pipeline.

### Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret |
| `TF_VAR_STOCK_API_KEY` | Massive API key (Terraform picks this up automatically) |

---

## Manual Lambda Testing

Trigger the ingestion Lambda on demand (useful for testing outside market hours):

```bash
aws lambda invoke \
  --function-name stock-movers-ingestion-prod \
  --payload '{}' \
  /tmp/response.json

cat /tmp/response.json
```

Check CloudWatch logs:

```bash
aws logs tail /aws/lambda/stock-movers-ingestion-prod --follow
```

Test the retrieval endpoint directly:

```bash
curl -s $(cd terraform && terraform output -raw api_endpoint) | python3 -m json.tool
```

---

## Tear Down

```bash
cd terraform
terraform destroy
```

This removes all AWS resources. The DynamoDB table, Lambda functions, API Gateway, S3 bucket, and Secrets Manager secret are all deleted.

> Note: The S3 bucket must be empty before it can be deleted. If `terraform destroy` fails on the bucket, empty it first:
> ```bash
> aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive
> ```

---

## Z-Score Statistical Significance

Each day's winning stock is evaluated against its own 90-day history using a **z-score**:

```
z = (today_pct_change - mean_90d) / stdev_90d
```

| Field | Meaning |
|---|---|
| `z_score` | How many standard deviations today's move is from the ticker's 90-day mean |
| `is_significant` | `true` when `abs(z_score) > 2.0` — approximately the top 5% of historical moves |

A move flagged as significant (⚠️ **Unusual Move** on the frontend) suggests the stock is behaving in a statistically abnormal way relative to its own recent history — not just that it moved a lot in absolute terms.

If the historical data fetch fails for any reason, `z_score` is stored as `null` and `is_significant` defaults to `false` — the daily winner record is still written.

---

## Repository Structure

```
stock-movers/
├── .github/
│   └── workflows/
│       └── deploy.yml           # CI/CD pipeline
├── terraform/
│   ├── main.tf                  # Root — wires all modules
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example # Safe template — commit this
│   └── modules/
│       ├── dynamodb/
│       ├── secrets_manager/
│       ├── iam/
│       ├── lambda/
│       ├── eventbridge/
│       ├── api_gateway/
│       └── s3/
├── lambda/
│   ├── ingestion/
│   │   ├── handler.py
│   │   └── requirements.txt
│   └── retrieval/
│       ├── handler.py
│       └── requirements.txt
├── frontend/
│   └── index.html
├── .gitignore
└── README.md
```
