provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "stage4-ecs"
      Managed = "terraform"
    }
  }
}
