import hmac
import json
import logging
import os
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])
secrets = boto3.client("secretsmanager")

REQUIRE_ORIGIN_VERIFY = os.environ.get("REQUIRE_ORIGIN_VERIFY", "true") == "true"

# Read once per warm container, not on every request.
_origin_secret = None


def get_origin_secret():
    global _origin_secret
    if _origin_secret is None:
        _origin_secret = secrets.get_secret_value(SecretId=os.environ["SECRET_ARN"])["SecretString"]
    return _origin_secret


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),  # default=str handles DynamoDB Decimals
    }


def caller_id(event):
    """User id (the 'sub' claim) from the Cognito token API Gateway already verified."""
    auth = (event.get("requestContext") or {}).get("authorizer") or {}
    claims = auth.get("claims") or (auth.get("jwt") or {}).get("claims") or {}
    return claims.get("sub")


def handler(event, context):
    # 1. Only accept requests that came through CloudFront (and therefore WAF).
    if REQUIRE_ORIGIN_VERIFY:
        headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
        provided = headers.get("x-origin-verify", "")
        if not hmac.compare_digest(provided.encode(), get_origin_secret().encode()):
            return respond(403, {"error": "Forbidden"})

    # 2. API Gateway already checked the token; we need to know who the user is.
    owner = caller_id(event)
    if not owner:
        return respond(401, {"error": "Unauthorized"})

    method = event.get("httpMethod")

    try:
        if method == "POST":
            body = json.loads(event.get("body") or "{}", parse_float=Decimal)
            item_id = body.get("id") if isinstance(body, dict) else None
            if not isinstance(item_id, str) or not item_id:
                return respond(400, {"error": "Body must be a JSON object with a non-empty string 'id'"})

            # The owner always comes from the verified token, never from the request body.
            item = {**body, "owner": owner}
            table.put_item(
                Item=item,
                # Create a new item, or update one you already own; never overwrite someone else's.
                ConditionExpression="attribute_not_exists(id) OR #owner = :owner",
                ExpressionAttributeNames={"#owner": "owner"},
                ExpressionAttributeValues={":owner": owner},
            )
            return respond(200, {"message": "Item created"})

        if method == "GET":
            item_id = (event.get("queryStringParameters") or {}).get("id")
            if not item_id:
                return respond(400, {"error": "Missing query parameter 'id'"})

            item = table.get_item(Key={"id": item_id}).get("Item")
            # Someone else's item looks exactly like a missing one.
            if not item or item.get("owner") != owner:
                return respond(404, {"error": "Not found"})
            return respond(200, item)

        return respond(400, {"error": "Unsupported method"})

    except json.JSONDecodeError:
        return respond(400, {"error": "Body is not valid JSON"})
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return respond(409, {"error": "Item belongs to another user"})
        logger.exception("DynamoDB error")
        return respond(500, {"error": "Internal server error"})
    except Exception:
        logger.exception("Unhandled error")
        return respond(500, {"error": "Internal server error"})
