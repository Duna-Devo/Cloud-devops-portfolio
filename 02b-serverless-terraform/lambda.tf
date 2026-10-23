############################################
# IAM role for the Lambda: only what the code actually does
############################################
resource "aws_iam_role" "lambda_role" {
  name = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-least-privilege"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ItemsTable"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.items.arn
      },
      {
        Sid      = "ReadOneSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.origin_verify.arn
      },
      {
        Sid      = "SendToDeadLetterQueue"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        # X-Ray does not support resource-level permissions.
        Sid      = "XRayTracing"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

############################################
# Lambda function (code is zipped by Terraform, no committed binary)
############################################
# The zip is built from build/lambda-src, which scripts/bundle_lambda.sh fills with the
# handler plus the X-Ray SDK. Run that script before terraform plan or apply.
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/build/lambda-src"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}-handler"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "api_handler" {
  function_name    = "${local.name}-handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  timeout          = 10
  memory_size      = 256
  publish          = true # every code change creates an immutable numbered version

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.items.name
      SECRET_ARN = aws_secretsmanager_secret.origin_verify.arn
      # Only enforced when CloudFront sits in front of the API.
      REQUIRE_ORIGIN_VERIFY = tostring(var.enable_edge)
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda_policy]
}

# API Gateway calls the "live" alias, not $LATEST. Rolling back a bad release
# is one command: point the alias at the previous version.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.api_handler.function_name
  function_version = aws_lambda_function.api_handler.version
}
