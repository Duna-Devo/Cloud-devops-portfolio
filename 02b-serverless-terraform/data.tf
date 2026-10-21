############################################
# DynamoDB: where the items are stored
############################################
resource "aws_dynamodb_table" "items" {
  name         = "${local.name}-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Restore the table to any second in the last 35 days (accidental deletes/overwrites).
  point_in_time_recovery {
    enabled = true
  }

  # Encryption at rest (AWS-managed key).
  server_side_encryption {
    enabled = true
  }

  # In prod the table cannot be deleted until this is switched off on purpose.
  deletion_protection_enabled = var.environment == "prod"
}

############################################
# SQS dead-letter queue
# Catches events that failed after Lambda's automatic retries.
# NOTE: this only applies to ASYNCHRONOUS invocations (events, queues).
# A normal API request that fails returns an error to the caller instead.
############################################
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

############################################
# Secrets Manager: shared secret that proves a request came through CloudFront.
# CloudFront adds it as a header; Lambda rejects requests without it, so the
# API Gateway URL cannot be used to bypass WAF.
############################################
resource "random_password" "origin_verify" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "origin_verify" {
  name                    = "${local.name}/origin-verify"
  description             = "Header value CloudFront sends so Lambda can reject direct API Gateway calls"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0
}

resource "aws_secretsmanager_secret_version" "origin_verify" {
  secret_id     = aws_secretsmanager_secret.origin_verify.id
  secret_string = random_password.origin_verify.result
}
