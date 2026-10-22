# Remote state in S3 with lockfile locking. These roles are account-wide, so they
# have their own state file, separate from the dev, staging and prod states.
terraform {
  backend "s3" {
    bucket       = "duna-eks-tfstate"
    key          = "serverless-ci-roles/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
