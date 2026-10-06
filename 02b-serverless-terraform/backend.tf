terraform {
  backend "s3" {
    bucket       = "duna-eks-tfstate"
    key          = "serverless/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
