resource "aws_cloudwatch_log_group" "pods" {
  name              = "/${var.name}/pods"
  retention_in_days = 7
}

data "aws_iam_policy_document" "fargate_logging" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.pods.arn}:*"]
  }
}

resource "aws_iam_role_policy" "fargate_logging" {
  name   = "${var.name}-fargate-logging"
  role   = aws_iam_role.fargate.id
  policy = data.aws_iam_policy_document.fargate_logging.json
}
