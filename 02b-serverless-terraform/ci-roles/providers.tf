terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "cloud-devops-portfolio"
      Stage     = "2b-ci-roles"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# The GitHub OIDC provider already exists in the account (created for Stage 3).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
