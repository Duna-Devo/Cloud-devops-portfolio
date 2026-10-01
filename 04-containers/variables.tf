variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Name used across the ECR repo, ECS cluster/service, and container"
  type        = string
  default     = "stage4-app"
}

variable "container_port" {
  description = "Port the Flask app listens on inside the container"
  type        = number
  default     = 5000
}
