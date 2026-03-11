import calendar
import json
import logging
import os
import time
import traceback
from datetime import datetime
from decimal import Decimal
from email.utils import formatdate, parsedate

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
    "Cache-Control": "max-age=300, stale-while-revalidate=60",
}


def to_http_date(date_str):
    """Convert 'YYYY-MM-DD' to RFC 7231 HTTP date: 'Thu, 06 Mar 2026 00:00:00 GMT'."""
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    return formatdate(calendar.timegm(dt.timetuple()), usegmt=True)


def convert_decimals(obj):
    """Recursively convert DynamoDB Decimal types to float for JSON serialization."""
    if isinstance(obj, list):
        return [convert_decimals(i) for i in obj]
    if isinstance(obj, dict):
        return {k: convert_decimals(v) for k, v in obj.items()}
    if isinstance(obj, Decimal):
        return float(obj)
    return obj


def lambda_handler(event, context):
    table_name = os.environ["DYNAMODB_TABLE"]

    try:
        params = event.get("queryStringParameters") or {}
        try:
            days = max(1, min(int(params.get("days", 7)), 90))
        except (ValueError, TypeError):
            days = 7

        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(table_name)

        response = table.scan()
        items = response.get("Items", [])

        # Handle DynamoDB pagination
        while "LastEvaluatedKey" in response:
            response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
            items.extend(response.get("Items", []))

        # Sort descending by date, then keep the N most recent trading day records
        items.sort(key=lambda x: x["date"], reverse=True)
        items = items[:days]

        # Remove TTL from response payload — internal implementation detail
        for item in items:
            item.pop("ttl", None)

        movers = convert_decimals(items)
        last_modified = to_http_date(items[0]["date"]) if items else None

        # Conditional request: return 304 if data hasn't changed since client's copy
        if last_modified:
            ims = (event.get("headers") or {}).get("if-modified-since")
            if ims:
                ims_ts = time.mktime(parsedate(ims))
                lm_ts = calendar.timegm(
                    datetime.strptime(items[0]["date"], "%Y-%m-%d").timetuple()
                )
                if lm_ts <= ims_ts:
                    logger.info("304 Not Modified — data unchanged since %s", items[0]["date"])
                    return {
                        "statusCode": 304,
                        "headers": {**CORS_HEADERS, "Last-Modified": last_modified},
                        "body": "",
                    }

        body = json.dumps({
            "movers": movers,
            "count": len(movers),
            "generated_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        })

        response_headers = {**CORS_HEADERS}
        if last_modified:
            response_headers["Last-Modified"] = last_modified

        logger.info("Returning %d movers (requested %d)", len(movers), days)
        return {
            "statusCode": 200,
            "headers": response_headers,
            "body": body,
        }

    except Exception:
        logger.error("Error in retrieval Lambda:\n%s", traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Internal server error"}),
        }
