variable "github_org" {
  description = "GitHub organisation or user that owns the repo"
  type        = string
  default     = "Duna-Devo"
}

variable "github_repo" {
  description = "Repository the pipeline runs in"
  type        = string
  default     = "Cloud-devops-portfolio"
}

variable "state_bucket" {
  description = "S3 bucket that holds the Terraform state"
  type        = string
  default     = "duna-eks-tfstate"
}
