variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "stage4"
}

variable "vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

variable "container_port" {
  type    = number
  default = 5000
}
