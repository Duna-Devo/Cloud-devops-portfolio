terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "duna-eks-tfstate"
    key          = "jenkins/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR form, e.g. 1.2.3.4/32"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Jenkins UI from my IP only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-sg" }
}

resource "aws_iam_role" "jenkins_role" {
  name = "jenkins-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins-ec2-profile"
  role = aws_iam_role.jenkins_role.name
}


data "aws_caller_identity" "me" {}

resource "aws_iam_role_policy" "jenkins_serverless" {
  name = "jenkins-serverless-deploy"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "arn:aws:dynamodb:us-east-1:${data.aws_caller_identity.me.account_id}:table/serverless-items"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
          "iam:TagRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy",
          "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/serverless-lambda-role"
      },
      {
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.me.account_id}:function:serverless-api-handler"
      },
      {
        Effect   = "Allow"
        Action   = "apigateway:*"
        Resource = [
          "arn:aws:apigateway:us-east-1::/apis",
          "arn:aws:apigateway:us-east-1::/apis/*",
          "arn:aws:apigateway:us-east-1::/tags/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::duna-eks-tfstate"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::duna-eks-tfstate/serverless/*"
      }
    ]
  })
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = "t3.small"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
  }

  tags = { Name = "jenkins-server" }
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}
