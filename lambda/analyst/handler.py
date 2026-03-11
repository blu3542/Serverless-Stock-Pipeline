import json
import logging
import os
import traceback
from datetime import datetime, timedelta
from decimal import Decimal

import anthropic
import boto3
from boto3.dynamodb.conditions import Attr

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
}

SYSTEM_PROMPT = """You are a financial data analyst assistant for a stock market dashboard.
You have access to daily "top mover" data — the single stock with the
highest absolute % change each day from a watchlist of: AAPL, MSFT,
GOOGL, AMZN, TSLA, NVDA.

Each record includes: date, ticker, % change (signed), open price,
close price, percentile rank (0–100, based on 90 days of historical moves),
and whether the move was statistically significant (percentile rank >= 85
means the move is in the top 15% of historical moves for that stock).

Answer the user's question using only the data provided. Be concise —
2-4 sentences. If a move was statistically significant, mention it.
If the data doesn't contain enough information to answer, say so clearly.
Do not speculate beyond what the data supports."""


def convert_decimals(obj):
    if isinstance(obj, list):
        return [convert_decimals(i) for i in obj]
    if isinstance(obj, dict):
        return {k: convert_decimals(v) for k, v in obj.items()}
    if isinstance(obj, Decimal):
        return float(obj)
    return obj


def format_records(items):
    lines = []
    for item in items:
        date = item.get("date", "?")
        ticker = item.get("ticker", "?")
        pct = item.get("pct_change", 0)
        close = item.get("close_price", 0)
        percentile = item.get("percentile_rank")
        significant = item.get("is_significant", False)

        pct_str = f"+{pct:.2f}%" if pct >= 0 else f"{pct:.2f}%"
        percentile_str = f"{percentile:.1f}th percentile" if percentile is not None else "N/A"
        sig_str = "YES" if significant else "NO"
        lines.append(
            f"Date: {date} | Winner: {ticker} | Change: {pct_str} | "
            f"Close: ${close:.2f} | Percentile: {percentile_str} | Significant: {sig_str}"
        )
    return "\n".join(lines)


def get_anthropic_api_key(secret_arn):
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_arn)
    secret = json.loads(response["SecretString"])
    return secret["api_key"]


def lambda_handler(event, context):
    table_name = os.environ["DYNAMODB_TABLE"]
    secret_arn = os.environ["ANTHROPIC_SECRET_ARN"]

    # Parse request body
    try:
        body = json.loads(event.get("body") or "{}")
        question = body.get("question", "").strip()
        if not question:
            return {
                "statusCode": 400,
                "headers": CORS_HEADERS,
                "body": json.dumps({"error": "Missing required field: question"}),
            }
        context_days = min(int(body.get("context_days", 7)), 30)
    except (json.JSONDecodeError, ValueError) as e:
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": f"Invalid request body: {str(e)}"}),
        }

    # Fetch DynamoDB records
    try:
        today = datetime.utcnow().date()
        cutoff = (today - timedelta(days=context_days)).isoformat()

        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(table_name)

        response = table.scan(FilterExpression=Attr("date").gte(cutoff))
        items = response.get("Items", [])

        while "LastEvaluatedKey" in response:
            response = table.scan(
                FilterExpression=Attr("date").gte(cutoff),
                ExclusiveStartKey=response["LastEvaluatedKey"],
            )
            items.extend(response.get("Items", []))

        items.sort(key=lambda x: x["date"], reverse=True)
        for item in items:
            item.pop("ttl", None)
        items = convert_decimals(items)

    except Exception:
        logger.error("DynamoDB fetch failed:\n%s", traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Failed to fetch market data"}),
        }

    if not items:
        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": json.dumps({
                "answer": "No market data is available yet. Data is ingested daily after market close.",
                "ticker_referenced": None,
                "data_used": [],
            }),
        }

    # Build prompt
    formatted = format_records(items)
    user_prompt = f"Here is the recent top mover data:\n\n{formatted}\n\nUser question: {question}"

    # Call Anthropic API
    try:
        api_key = get_anthropic_api_key(secret_arn)
        client = anthropic.Anthropic(api_key=api_key)

        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            tools=[{"type": "web_search_20250305", "name": "web_search"}],
            messages=[{"role": "user", "content": user_prompt}],
        )
        answer = " ".join(
            block.text for block in message.content if block.type == "text"
        )

    except Exception:
        logger.error("Anthropic API call failed:\n%s", traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "AI analyst is temporarily unavailable"}),
        }

    # Extract referenced ticker (best-effort: find first ticker mention in answer)
    watchlist = ["AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "NVDA"]
    ticker_referenced = next((t for t in watchlist if t in answer.upper()), None)

    logger.info("Answered question about %d records; ticker_referenced=%s", len(items), ticker_referenced)

    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": json.dumps({
            "answer": answer,
            "ticker_referenced": ticker_referenced,
            "data_used": items,
        }),
    }
