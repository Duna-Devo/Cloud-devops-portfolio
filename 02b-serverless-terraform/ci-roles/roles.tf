# Two roles for the serverless pipeline, replacing AdministratorAccess:
#   serverless-plan  - read-only, used by pull requests
#   serverless-apply - scoped write access, used by deploys from main only
#
# GitHub tokens for an organisation account include numeric IDs in the "sub"
# claim (for example repo:Duna-Devo@123/Cloud-devops-portfolio@456:...), so the
# trust conditions use a wildcard for the ID part and are exact for everything else.

locals {
  account_id = data.aws_caller_identity.current.account_id
  repo_match = "repo:${var.github_org}*/${var.github_repo}*"
  name_match = "serverless-*"
}

# ---------------------------------------------------------------- plan role --

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pull request runs only.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_match}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "serverless-plan"
  description        = "Read-only role for terraform plan on pull requests"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state" {
  # Plan only reads real infrastructure, but it still needs to read the state
  # and write the lock file next to it.
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/serverless/*"]
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:us-east-1:${local.account_id}:secret:${local.name_match}"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "state-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# --------------------------------------------------------------- apply role --

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only jobs that run in the dev, staging or production GitHub environments.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.repo_match}:environment:dev",
        "${local.repo_match}:environment:staging",
        "${local.repo_match}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = "serverless-apply"
  description        = "Scoped deploy role for the serverless stack"
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
}

data "aws_iam_policy_document" "apply" {
  # Terraform state and lock file.
  statement {
    sid       = "StateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/serverless/*"]
  }

  # Lambda: the function, its alias and versions, and permissions.
  statement {
    sid       = "Lambda"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:us-east-1:${local.account_id}:function:${local.name_match}"]
  }

  # IAM: only roles named serverless-*, which keeps the CI roles themselves out
  # of reach. This role cannot edit serverless-plan or serverless-apply.
  statement {
    sid = "ServerlessRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole", "iam:PassRole",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:UpdateAssumeRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.name_match}"]
  }

  statement {
    sid       = "DenyCiRoles"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = [aws_iam_role.plan.arn, aws_iam_role.apply.arn]
  }

  # Data and messaging.
  statement {
    sid       = "DynamoDB"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account_id}:table/${local.name_match}"]
  }

  statement {
    sid       = "DynamoDBList"
    actions   = ["dynamodb:ListTables", "dynamodb:DescribeLimits"]
    resources = ["*"]
  }

  statement {
    sid       = "Sqs"
    actions   = ["sqs:*"]
    resources = ["arn:aws:sqs:us-east-1:${local.account_id}:${local.name_match}"]
  }

  statement {
    sid       = "Sns"
    actions   = ["sns:*"]
    resources = ["arn:aws:sns:us-east-1:${local.account_id}:${local.name_match}"]
  }

  statement {
    sid       = "SecretsManager"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:us-east-1:${local.account_id}:secret:${local.name_match}"]
  }

  statement {
    sid       = "KmsViaSecretsManager"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.us-east-1.amazonaws.com"]
    }
  }

  # Sign-in and the smoke test's temporary user.
  statement {
    sid       = "Cognito"
    actions   = ["cognito-idp:*"]
    resources = ["arn:aws:cognito-idp:us-east-1:${local.account_id}:userpool/*"]
  }

  statement {
    sid       = "CognitoCreate"
    actions   = ["cognito-idp:CreateUserPool", "cognito-idp:ListUserPools"]
    resources = ["*"]
  }

  # API Gateway (the HTTP API), CloudWatch, logs.
  statement {
    sid       = "ApiGateway"
    actions   = ["apigateway:*"]
    resources = ["arn:aws:apigateway:us-east-1::/*"]
  }

  statement {
    sid       = "CloudWatchAlarms"
    actions   = ["cloudwatch:*"]
    resources = ["*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:*"]
    resources = ["*"]
  }

  # The front door. These services do not support name-based scoping, so they
  # are limited by service only.
  statement {
    sid = "FrontDoor"
    actions = [
      "cloudfront:*", "wafv2:*", "acm:*", "route53:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "serverless-deploy"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
