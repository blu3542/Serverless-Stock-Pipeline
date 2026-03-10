import json
import logging
import os
import traceback
from datetime import datetime, timedelta
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
}


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

        today = datetime.utcnow().date()
        cutoff = (today - timedelta(days=days)).isoformat()

        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(table_name)

        response = table.scan(
            FilterExpression=Attr("date").gte(cutoff)
        )
        items = response.get("Items", [])

        # Handle DynamoDB pagination
        while "LastEvaluatedKey" in response:
            response = table.scan(
                FilterExpression=Attr("date").gte(cutoff),
                ExclusiveStartKey=response["LastEvaluatedKey"],
            )
            items.extend(response.get("Items", []))

        # Sort descending by date (most recent first)
        items.sort(key=lambda x: x["date"], reverse=True)

        # Remove TTL from response payload — internal implementation detail
        for item in items:
            item.pop("ttl", None)

        movers = convert_decimals(items)

        body = json.dumps({
            "movers": movers,
            "count": len(movers),
            "generated_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        })

        logger.info("Returning %d movers since %s", len(movers), cutoff)
        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": body,
        }

    except Exception:
        logger.error("Error in retrieval Lambda:\n%s", traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Internal server error"}),
        }
