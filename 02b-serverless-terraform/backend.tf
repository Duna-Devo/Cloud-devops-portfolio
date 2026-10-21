# Remote state in S3 with lockfile locking. The state key is NOT set here: each
# environment (dev, staging, prod) has its own state file, passed at init time:
#
#   terraform init -backend-config="key=serverless/<env>/terraform.tfstate"
terraform {
  backend "s3" {
    bucket       = "duna-eks-tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
