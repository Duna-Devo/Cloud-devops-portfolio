provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "stage4-ecs"
      Managed = "terraform"
    }
  }
}
