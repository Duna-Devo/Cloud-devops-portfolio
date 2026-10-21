############################################
# API Gateway (HTTP API): checks the token, then calls Lambda
############################################
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${local.name}-http-api"
  protocol_type = "HTTP"
}

# The handler expects the version 1.0 event shape (event["httpMethod"]).
# This must stay "1.0" or Lambda fails before running and the API returns a
# generic 500 (the bug found in the first version of this stage).
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.live.invoke_arn
  payload_format_version = "1.0"
}

# Rejects requests without a valid Cognito token (HTTP 401) before Lambda runs.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  name             = "${local.name}-cognito"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app.id]
    issuer   = "https://${aws_cognito_user_pool.main.endpoint}"
  }
}

resource "aws_apigatewayv2_route" "items_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "ANY /items"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name}-http-api"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  # Caps how hard anyone can hit the backend (protects Lambda and the bill).
  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      path           = "$context.path"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
      authError      = "$context.authorizer.error"
    })
  }
}

# Allows API Gateway (this API only) to invoke the "live" alias.
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
