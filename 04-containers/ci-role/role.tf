data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  region     = "us-east-1"
  account_id = data.aws_caller_identity.current.account_id
  ecr_repo   = "arn:aws:ecr:${local.region}:${local.account_id}:repository/stage4-app"

  environments = {
    staging = {
      name       = "stage4"
      github_env = "staging"
      push_image = true
    }
    production = {
      name       = "stage4-prod"
      github_env = "production"
      push_image = false
    }
  }
}

data "aws_iam_policy_document" "trust" {
  for_each = local.environments

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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Duna-Devo*/Cloud-devops-portfolio*:environment:${each.value.github_env}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = local.environments

  name               = "stage4-deploy-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json
}

data "aws_iam_policy_document" "deploy" {
  for_each = local.environments

  dynamic "statement" {
    for_each = [for s in ["login"] : s if each.value.push_image]
    content {
      sid       = "EcrLogin"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = [for s in ["push"] : s if each.value.push_image]
    content {
      sid = "EcrPush"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = [local.ecr_repo]
    }
  }

  statement {
    sid       = "TaskDefinitions"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "Service"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:aws:ecs:${local.region}:${local.account_id}:service/${each.value.name}-cluster/${each.value.name}-service"]
  }

  statement {
    sid       = "ListTasks"
    actions   = ["ecs:ListTasks"]
    resources = ["arn:aws:ecs:${local.region}:${local.account_id}:cluster/${each.value.name}-cluster"]
  }

  statement {
    sid       = "DescribeTasks"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:aws:ecs:${local.region}:${local.account_id}:task/${each.value.name}-cluster/*"]
  }

  statement {
    sid       = "PassExecutionRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${each.value.name}-ecs-execution"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "FindFrontDoor"
    actions   = ["cloudfront:ListDistributions"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.environments

  name   = "stage4-deploy-${each.key}"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.deploy[each.key].json
}
