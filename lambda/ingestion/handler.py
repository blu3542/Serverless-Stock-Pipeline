import json
import logging
import os
import statistics
import time
import traceback
from datetime import datetime, timedelta, timezone

import boto3
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

MASSIVE_BASE = "https://api.massive.com"


def fetch_with_retry(url, max_retries=3):
    """GET a URL with retry on transient errors only.
    4xx errors are not retried — they won't resolve on retry.
    """
    last_exc = None
    for attempt in range(max_retries):
        try:
            resp = requests.get(url, timeout=10)
            if 400 <= resp.status_code < 500:
                resp.raise_for_status()  # raise immediately, no retry
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.HTTPError as exc:
            if exc.response is not None and 400 <= exc.response.status_code < 500:
                raise
            last_exc = exc
            if attempt < max_retries - 1:
                time.sleep(13 * (attempt + 1))
        except Exception as exc:
            last_exc = exc
            if attempt < max_retries - 1:
                time.sleep(13 * (attempt + 1))
    raise last_exc


def get_api_key(secret_arn):
    client = boto3.client("secretsmanager")
    secret = client.get_secret_value(SecretId=secret_arn)
    return json.loads(secret["SecretString"])["api_key"]


def fetch_most_recent_ohlc(ticker, api_key, target_date=None):
    """Return (date_str, open, close) for the most recent available trading day,
    or for a specific target_date when backfilling.
    Queries a 7-day window ending on target_date (or today) and takes the latest
    bar — handles free-tier data lag and weekends/holidays automatically.
    """
    to_date = target_date if target_date else datetime.now(timezone.utc).date()
    from_date = to_date - timedelta(days=7)
    url = (
        f"{MASSIVE_BASE}/v2/aggs/ticker/{ticker}/range/1/day"
        f"/{from_date.isoformat()}/{to_date.isoformat()}"
        f"?adjusted=true&sort=asc&apiKey={api_key}"
    )
    data = fetch_with_retry(url)
    if data.get("status") not in ("OK", "DELAYED"):
        raise ValueError(f"Unexpected status for {ticker}: {data.get('status')}")
    results = data.get("results", [])
    if not results:
        raise ValueError(f"No recent data returned for {ticker}")

    if target_date:
        # Backfill: find the bar whose date matches target_date exactly.
        for bar in reversed(results):
            bar_dt = datetime.fromtimestamp(bar["t"] / 1000, tz=timezone.utc).date()
            if bar_dt == target_date:
                return bar_dt.isoformat(), float(bar["o"]), float(bar["c"])
        raise ValueError(f"No bar found for {ticker} on {target_date.isoformat()}")

    bar = results[-1]  # most recent trading day
    bar_date = datetime.fromtimestamp(bar["t"] / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    return bar_date, float(bar["o"]), float(bar["c"])


def fetch_historical_changes(ticker, as_of_date, api_key):
    """Return list of daily % changes over the 90 days ending on as_of_date."""
    from_date = (as_of_date - timedelta(days=90)).isoformat()
    to_date = as_of_date.isoformat()
    url = (
        f"{MASSIVE_BASE}/v2/aggs/ticker/{ticker}/range/1/day"
        f"/{from_date}/{to_date}"
        f"?adjusted=true&sort=asc&limit=120&apiKey={api_key}"
    )
    data = fetch_with_retry(url)
    if data.get("status") not in ("OK", "DELAYED"):
        raise ValueError(f"Unexpected historical status for {ticker}: {data.get('status')}")
    results = data.get("results", [])
    if not results:
        raise ValueError(f"No historical bars returned for {ticker}")
    return [((bar["c"] - bar["o"]) / bar["o"]) * 100 for bar in results]


def lambda_handler(event, context):
    table_name = os.environ["DYNAMODB_TABLE"]
    secret_arn = os.environ["SECRET_ARN"]
    watchlist = [t.strip() for t in os.environ["STOCK_WATCHLIST"].split(",")]

    # --- Backfill mode: invoke with {"backfill_date": "2025-03-04"} to correct a specific date.
    # Backfill always writes, bypassing the idempotency guard.
    backfill_date_str = event.get("backfill_date") if isinstance(event, dict) else None
    target_date = None
    if backfill_date_str:
        target_date = datetime.strptime(backfill_date_str, "%Y-%m-%d").date()
        logger.info("Backfill mode: targeting %s", backfill_date_str)

    # --- Retrieve API key ---
    try:
        api_key = get_api_key(secret_arn)
    except Exception:
        logger.critical("Failed to retrieve API key from Secrets Manager:\n%s", traceback.format_exc())
        raise

    # --- Fetch most recent available OHLC for each ticker ---
    valid_results = []
    record_date = None
    for ticker in watchlist:
        try:
            bar_date, open_price, close_price = fetch_most_recent_ohlc(ticker, api_key, target_date=target_date)
            pct_change = ((close_price - open_price) / open_price) * 100
            valid_results.append({
                "ticker": ticker,
                "date": bar_date,
                "open_price": open_price,
                "close_price": close_price,
                "pct_change": pct_change,
            })
            if record_date is None:
                record_date = bar_date
            logger.info("Fetched %s [%s]: open=%.2f close=%.2f pct=%.2f%%",
                        ticker, bar_date, open_price, close_price, pct_change)
        except Exception:
            logger.error("Failed to fetch OHLC for %s:\n%s", ticker, traceback.format_exc())
        time.sleep(13)  # respect 5 calls/minute free tier limit

    if len(valid_results) < 3:
        logger.critical(
            "Only %d tickers returned valid data (need >= 3). Aborting without writing to DynamoDB.",
            len(valid_results),
        )
        return {"statusCode": 500, "body": "Insufficient ticker data"}

    # --- Find the day's winner (largest absolute % change) ---
    winner = max(valid_results, key=lambda x: abs(x["pct_change"]))
    logger.info("Winner: %s with %.2f%% change on %s", winner["ticker"], winner["pct_change"], record_date)

    # --- Compute z-score for winner ---
    z_score = None
    is_significant = False
    try:
        as_of = datetime.strptime(record_date, "%Y-%m-%d").date()
        historical_changes = fetch_historical_changes(winner["ticker"], as_of, api_key)
        if len(historical_changes) >= 2:
            mean = statistics.mean(historical_changes)
            std = statistics.stdev(historical_changes)
            if std != 0:
                z_score = round((winner["pct_change"] - mean) / std, 2)
                is_significant = abs(z_score) > 2.0
                logger.info("Z-score for %s: %.2f (significant=%s)", winner["ticker"], z_score, is_significant)
            else:
                logger.warning("Std dev is 0 for %s — skipping z-score", winner["ticker"])
        else:
            logger.warning("Not enough historical data for %s to compute z-score", winner["ticker"])
    except Exception:
        logger.error("Failed to compute z-score for %s — recording null:\n%s",
                     winner["ticker"], traceback.format_exc())

    # --- Write to DynamoDB ---
    from decimal import Decimal
    ttl = int((datetime.now(timezone.utc) + timedelta(days=90)).timestamp())

    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)

    item = {
        "date": record_date,
        "ticker": winner["ticker"],
        "pct_change": Decimal(str(round(winner["pct_change"], 4))),
        "close_price": Decimal(str(round(winner["close_price"], 4))),
        "open_price": Decimal(str(round(winner["open_price"], 4))),
        "is_significant": is_significant,
        "ttl": ttl,
    }
    if z_score is not None:
        item["z_score"] = Decimal(str(round(z_score, 2)))

    # --- Idempotency guard (skipped in backfill mode) ---
    # Prevents overwriting a valid record with a stale bar from a lagging API.
    if not target_date:
        existing = table.get_item(Key={"date": record_date}).get("Item")
        if existing:
            logger.warning(
                "Record for %s already exists in DynamoDB — API may still be lagging. Skipping write.",
                record_date,
            )
            return {"statusCode": 200, "body": json.dumps({"skipped": True, "reason": "already_exists", "date": record_date})}

    table.put_item(Item=item)
    logger.info("Successfully wrote record to DynamoDB for %s", record_date)

    return {
        "statusCode": 200,
        "body": json.dumps({
            "date": record_date,
            "winner": winner["ticker"],
            "pct_change": winner["pct_change"],
            "z_score": z_score,
            "is_significant": is_significant,
        }),
    }
