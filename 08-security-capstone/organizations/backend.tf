terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "duna-eks-tfstate"
    key          = "stage8/organizations/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
