provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "cloud-devops-portfolio"
      Stage     = "08-security-capstone"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_organizations_organization" "main" {
  feature_set          = "ALL"
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "sandbox"
  parent_id = aws_organizations_organization.main.roots[0].id
}

resource "aws_organizations_account" "sandbox" {
  name              = "stage8-sandbox"
  email             = var.member_email
  parent_id         = aws_organizations_organizational_unit.sandbox.id
  close_on_deletion = true

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_policy" "guardrails" {
  name       = "stage8-guardrails"
  type       = "SERVICE_CONTROL_POLICY"
  depends_on = [aws_organizations_organization.main]

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyOtherRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*", "organizations:*", "sts:*", "support:*", "account:*",
          "billing:*", "budgets:*", "ce:*", "health:*",
          "cloudfront:*", "route53:*", "wafv2:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["us-east-1"]
          }
        }
      },
      {
        Sid      = "DenyLeavingTheOrganization"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      },
      {
        Sid      = "DenyStoppingCloudTrail"
        Effect   = "Deny"
        Action   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "sandbox" {
  policy_id = aws_organizations_policy.guardrails.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}
