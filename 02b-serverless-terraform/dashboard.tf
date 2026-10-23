############################################
# One CloudWatch dashboard for the whole request path
############################################
data "aws_region" "current" {}

locals {
  dash_region = data.aws_region.current.name
  waf_name    = one(aws_wafv2_web_acl.api[*].name)

  dashboard_base_widgets = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        title  = "API Gateway: requests and errors"
        region = local.dash_region
        view   = "timeSeries"
        period = 300
        stat   = "Sum"
        metrics = [
          ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.http_api.id],
          ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.http_api.id],
          ["AWS/ApiGateway", "5xx", "ApiId", aws_apigatewayv2_api.http_api.id],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 0
      width  = 12
      height = 6
      properties = {
        title  = "API Gateway: latency (ms), total vs waiting on Lambda"
        region = local.dash_region
        view   = "timeSeries"
        period = 300
        stat   = "Average"
        metrics = [
          ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.http_api.id],
          ["AWS/ApiGateway", "IntegrationLatency", "ApiId", aws_apigatewayv2_api.http_api.id],
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        title  = "Lambda: invocations, errors, throttles"
        region = local.dash_region
        view   = "timeSeries"
        period = 300
        stat   = "Sum"
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.api_handler.function_name],
          ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.api_handler.function_name],
          ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.api_handler.function_name],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        title  = "Lambda: duration (ms), average and p95"
        region = local.dash_region
        view   = "timeSeries"
        period = 300
        metrics = [
          ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api_handler.function_name, { stat = "Average" }],
          ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api_handler.function_name, { stat = "p95" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        title  = "DynamoDB: throttled and failed requests"
        region = local.dash_region
        view   = "timeSeries"
        period = 300
        stat   = "Sum"
        metrics = [
          ["AWS/DynamoDB", "ReadThrottleEvents", "TableName", aws_dynamodb_table.items.name],
          ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", aws_dynamodb_table.items.name],
          ["AWS/DynamoDB", "SystemErrors", "TableName", aws_dynamodb_table.items.name],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        title  = "Dead-letter queue: messages waiting"
        region = local.dash_region
        view   = "timeSeries"
        period = 300
        stat   = "Maximum"
        metrics = [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.dlq.name],
        ]
      }
    },
  ]

  # Front-door widgets only exist when the front door is on. CloudFront and WAF
  # metrics for a CloudFront distribution are always published in us-east-1.
  dashboard_edge_widgets = [
    {
      type   = "metric"
      x      = 0
      y      = 18
      width  = 12
      height = 6
      properties = {
        title  = "CloudFront: requests and 5xx error rate"
        region = "us-east-1"
        view   = "timeSeries"
        period = 300
        metrics = [
          ["AWS/CloudFront", "Requests", "DistributionId", local.cloudfront_id, "Region", "Global", { stat = "Sum" }],
          ["AWS/CloudFront", "5xxErrorRate", "DistributionId", local.cloudfront_id, "Region", "Global", { stat = "Average", yAxis = "right" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 18
      width  = 12
      height = 6
      properties = {
        title  = "WAF: allowed vs blocked requests"
        region = "us-east-1"
        view   = "timeSeries"
        period = 300
        stat   = "Sum"
        metrics = [
          ["AWS/WAFV2", "AllowedRequests", "WebACL", local.waf_name, "Rule", "ALL", "Region", "Global"],
          ["AWS/WAFV2", "BlockedRequests", "WebACL", local.waf_name, "Rule", "ALL", "Region", "Global"],
        ]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "${local.name}-overview"

  dashboard_body = jsonencode({
    widgets = concat(
      local.dashboard_base_widgets,
      [for w in local.dashboard_edge_widgets : w if var.enable_edge],
    )
  })
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.overview.dashboard_name
}
