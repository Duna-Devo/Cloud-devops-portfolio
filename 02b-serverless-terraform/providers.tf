terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags automatically (cost reports, ownership).
  default_tags {
    tags = {
      Project     = "serverless-api"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "serverless-${var.environment}"
}
