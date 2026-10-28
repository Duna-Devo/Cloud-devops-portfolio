variable "alert_email" {
  type = string
}

resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:EventBridge cannot publish to a topic using the default AWS key, a customer-managed KMS key is a next step
  name = "stage8-security-alerts"
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  rules = {
    # Someone turns off or changes the audit trail
    trail-tampering = {
      description = "CloudTrail logging stopped, deleted or changed"
      pattern = {
        source        = ["aws.cloudtrail"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName   = ["StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors"]
        }
      }
    }
    # Someone signs in to the console as the root user
    root-login = {
      description = "Root user signed in to the console"
      pattern = {
        source        = ["aws.signin"]
        "detail-type" = ["AWS Console Sign In via CloudTrail"]
        detail = {
          userIdentity = { type = ["Root"] }
        }
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "security" {
  for_each      = local.rules
  name          = "stage8-${each.key}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)
}

resource "aws_cloudwatch_event_target" "email" {
  for_each = local.rules
  rule     = aws_cloudwatch_event_rule.security[each.key].name
  arn      = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      event = "$.detail.eventName"
      who   = "$.detail.userIdentity.arn"
      ip    = "$.detail.sourceIPAddress"
      time  = "$.time"
    }
    input_template = "\"Security alert: <event> by <who> from <ip> at <time>\""
  }
}
