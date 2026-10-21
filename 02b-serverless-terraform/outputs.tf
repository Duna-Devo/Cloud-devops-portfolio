output "api_url" {
  description = "Public API address (custom domain if set, otherwise the CloudFront domain)"
  value       = !var.enable_edge ? aws_apigatewayv2_api.http_api.api_endpoint : (local.use_domain ? "https://${var.domain_name}" : "https://${one(aws_cloudfront_distribution.api[*].domain_name)}")
}

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.app.id
}

output "lambda_function_name" {
  value = aws_lambda_function.api_handler.function_name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
