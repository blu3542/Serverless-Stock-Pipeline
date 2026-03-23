# Stock Movers

A fully automated, serverless AWS pipeline that tracks a watchlist of 6 tech stocks daily, identifies the single largest mover by absolute % change, and surfaces the results on a public frontend — with a statistical significance layer (z-score) that flags genuinely unusual moves and an AI Analyst chat feature powered by Claude.

---

## Architecture

```
                           ┌──────────────────────────────────────────────────────┐
                           │                      AWS                             │
                           │                                                      │
  Market close (5 PM EST)  │  ┌──────────────┐    ┌──────────────────────────┐   │
  ─────────────────────────┼─▶│  EventBridge │───▶│   Lambda: Ingestion      │   │
  cron(0 21 * * ? *)       │  └──────────────┘    │   (Python 3.12)          │   │
                           │                       │                          │   │
                           │  ┌─────────────────┐  │  1. Fetch OHLC for      │   │
                           │  │ Secrets Manager │◀─│     6 tickers           │   │
                           │  │ (Massive key +  │  │  2. Find winner         │   │
                           │  │  Anthropic key) │  │  3. Compute z-score     │   │
                           │  └─────────────────┘  │  4. Write to DB         │   │
                           │                       └────────────┬─────────────┘  │
                           │                                    │                │
                           │                       ┌────────────▼─────────────┐  │
                           │                       │        DynamoDB          │  │
                           │                       │     (one row / day)      │  │
                           │                       └────────────┬─────────────┘  │
                           │                                    │                │
                           │  ┌──────────────┐   ┌─────────────▼────────────┐   │
  Browser ─────────────────┼─▶│ API Gateway  │──▶│   Lambda: Retrieval      │   │
  GET /movers              │  │  REST API    │   │   (Python 3.12)          │   │
                           │  │              │   │   Last N days, JSON      │   │
                           │  │              │   └──────────────────────────┘   │
                           │  │              │                                   │
                           │  │              │   ┌──────────────────────────┐   │
  Browser ─────────────────┼─▶│              │──▶│   Lambda: Analyst        │   │
  POST /analyst            │  └──────────────┘   │   (Python 3.12)          │   │
                           │                      │                          │   │
                           │                      │  1. Read context from DB │   │
                           │                      │  2. Fetch Anthropic key  │   │
                           │                      │  3. Call Claude w/ web   │   │
                           │                      │     search               │   │
                           │                      └──────────────────────────┘   │
                           │                                                      │
  Browser ─────────────────┼─▶  S3 Static Website  (index.html)                  │
                           └──────────────────────────────────────────────────────┘
```

**Stock Watchlist:** `AAPL · MSFT · GOOGL · AMZN · TSLA · NVDA`

---

## Prerequisites

| Tool | Version |
|---|---|
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2+ |
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5 |
| [Python](https://www.python.org/downloads/) | 3.12 (for local Lambda testing only) |
| [Node.js](https://nodejs.org/) | 18+ (for the CLI only) |

You also need a [Massive API](https://massive.com) key for stock data and an [Anthropic API](https://console.anthropic.com/) key for the AI Analyst feature.

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
| `TF_VAR_ANTHROPIC_API_KEY` | Anthropic API key for the AI Analyst Lambda |

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

Test the analyst endpoint:

```bash
API=$(cd terraform && terraform output -raw api_endpoint | sed 's|/movers||')
curl -s -X POST "$API/analyst" \
  -H "Content-Type: application/json" \
  -d '{"question": "Why did NVDA move today?", "context_days": 7}' | python3 -m json.tool
```

---

## CLI

A TypeScript CLI (`stocks`) for querying the movers API directly from the terminal. Built with [Commander](https://github.com/tj/commander.js) and [Chalk](https://github.com/chalk/chalk) for colored output.

**Build:**

```bash
cd cli
npm install
npm run build
```

**Usage:**

```bash
stocks <ticker|all> [--days <n>]
```

| Argument / Flag | Description | Default |
|---|---|---|
| `<ticker>` | Stock ticker to filter (e.g. `TSLA`, `NVDA`) or `all` for every entry | required |
| `-d, --days <n>` | Number of days to fetch (1–90) | `7` |

```bash
# Show all top movers for the last 7 days
stocks all

# Filter to a specific ticker
stocks TSLA

# Custom date range
stocks NVDA --days 30
stocks all -d 14
```

**Output columns:**

```
Date            Ticker  % Change    Open        Close       Percentile  Significance
────────────────────────────────────────────────────────────────────────────────────
Fri, Mar 21     NVDA    +4.82%      $875.00     $917.24     94.3%       ⚠ Unusual Move
Thu, Mar 20     TSLA    -2.11%      $192.50     $188.44     31.0%       Normal
```

- **% Change** is green for gains, red for losses.
- **Percentile** is the ticker's historical percentile rank for that day's move.
- **Significance** shows `⚠ Unusual Move` (yellow) when the z-score exceeds ±2.0, otherwise `Normal`.

If no records match the requested ticker, the CLI lists which tickers are available in the returned data.

**Install globally via npm link:**

```bash
cd cli && npm link
stocks all
stocks TSLA --days 14
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

## AI Analyst

The frontend includes a chat interface that lets you ask natural language questions about recent stock movements. Questions are sent to the analyst Lambda via `POST /analyst`.

**Request:**
```json
{ "question": "Why did NVDA move so much this week?", "context_days": 7 }
```

**Response:**
```json
{ "answer": "NVDA surged X% on ... (natural language analysis)" }
```

The Lambda fetches the last N days of DynamoDB records as context, then calls **Claude (claude-sonnet-4-6)** with the `web_search` tool enabled — so answers combine your historical data with real-time news retrieval. The Anthropic API key is read from Secrets Manager at runtime (never hardcoded).

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
│   ├── retrieval/
│   │   ├── handler.py
│   │   └── requirements.txt
│   └── analyst/
│       ├── handler.py           # Proxies questions to Claude w/ web search
│       └── requirements.txt
├── frontend/
│   └── index.html
├── cli/                         # TypeScript CLI (stocks <ticker>)
│   ├── src/
│   │   ├── index.ts
│   │   ├── api.ts
│   │   └── formatter.ts
│   ├── package.json
│   └── tsconfig.json
├── .gitignore
└── README.md
```
