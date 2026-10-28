terraform {
  backend "s3" {
    bucket       = "duna-eks-tfstate"
    key          = "stage8/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
