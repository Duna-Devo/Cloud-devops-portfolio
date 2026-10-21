############################################
# Alerting: CloudWatch alarms -> SNS -> email
############################################
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarms = {
    lambda-errors = {
      description = "Lambda function is throwing errors"
      namespace   = "AWS/Lambda"
      metric      = "Errors"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { FunctionName = aws_lambda_function.api_handler.function_name }
    }
    lambda-throttles = {
      description = "Lambda is being throttled"
      namespace   = "AWS/Lambda"
      metric      = "Throttles"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { FunctionName = aws_lambda_function.api_handler.function_name }
    }
    api-5xx = {
      description = "API Gateway is returning server errors"
      namespace   = "AWS/ApiGateway"
      metric      = "5xx"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { ApiId = aws_apigatewayv2_api.http_api.id }
    }
    dlq-not-empty = {
      description = "Failed events are waiting in the dead-letter queue"
      namespace   = "AWS/SQS"
      metric      = "ApproximateNumberOfMessagesVisible"
      statistic   = "Maximum"
      threshold   = 1
      dimensions  = { QueueName = aws_sqs_queue.dlq.name }
    }
    dynamodb-read-throttles = {
      description = "DynamoDB reads are being throttled"
      namespace   = "AWS/DynamoDB"
      metric      = "ReadThrottleEvents"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { TableName = aws_dynamodb_table.items.name }
    }
    dynamodb-write-throttles = {
      description = "DynamoDB writes are being throttled"
      namespace   = "AWS/DynamoDB"
      metric      = "WriteThrottleEvents"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { TableName = aws_dynamodb_table.items.name }
    }
    cloudfront-5xx-rate = {
      description = "More than 5% of requests through CloudFront fail with 5xx"
      namespace   = "AWS/CloudFront"
      metric      = "5xxErrorRate"
      statistic   = "Average"
      threshold   = 5
      dimensions  = { DistributionId = aws_cloudfront_distribution.api.id, Region = "Global" }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  dimensions          = each.value.dimensions
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
