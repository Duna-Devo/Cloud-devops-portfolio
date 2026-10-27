variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "stage6"
}

variable "vpc_cidr" {
  type    = string
  default = "10.3.0.0/16"
}
