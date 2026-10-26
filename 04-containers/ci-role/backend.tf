terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "duna-eks-tfstate"
    key          = "stage4-ci-role/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
