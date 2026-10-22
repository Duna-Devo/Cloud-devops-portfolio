variable "region" {
  description = "AWS region. Must be us-east-1: CloudFront certificates (ACM) and CloudFront WAF rules only live there."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "Use us-east-1: ACM certificates for CloudFront and CLOUDFRONT-scope WAF must be created there."
  }
}

variable "environment" {
  description = "Deployment environment. Names, state key and protections change with it."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "alert_email" {
  description = "Email address that receives CloudWatch alarm notifications (confirm the SNS subscription from the inbox)."
  type        = string
}

variable "enable_edge" {
  description = "Create the public front door (CloudFront, WAF, ACM, Route 53). Keep false while the account cannot create CloudFront distributions; the API is then reached directly at its API Gateway address and the CloudFront header check is turned off."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Custom API domain, e.g. api.example.com. Leave empty to use the default CloudFront domain (no Route 53 or ACM resources are created)."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID that contains domain_name. Required when domain_name is set."
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || var.hosted_zone_id != ""
    error_message = "hosted_zone_id is required when domain_name is set."
  }
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps Lambda and API access logs."
  type        = number
  default     = 30
}
