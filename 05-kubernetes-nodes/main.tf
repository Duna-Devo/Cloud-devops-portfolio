terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.prefix}eks-vpc" }
}

resource "aws_subnet" "eks_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${local.prefix}eks-subnet-a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "eks_subnet_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${local.prefix}eks-subnet-b"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.prefix}eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "${local.prefix}eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "main" {
  name     = "${local.prefix}duna-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.eks_subnet_a.id,
      aws_subnet.eks_subnet_b.id
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

terraform {
  backend "s3" {
    bucket       = "duna-eks-tfstate"
    key          = "05-kubernetes-nodes/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.prefix}duna-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.eks_private_a.id, aws_subnet.eks_private_b.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_route_table_association.eks_private_assoc_a,
    aws_route_table_association.eks_private_assoc_b
  ]
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags   = { Name = "${local.prefix}eks-igw" }
}

resource "aws_route_table" "eks_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = { Name = "${local.prefix}eks-rt" }
}

resource "aws_route_table_association" "eks_rt_assoc_a" {
  subnet_id      = aws_subnet.eks_subnet_a.id
  route_table_id = aws_route_table.eks_rt.id
}

resource "aws_route_table_association" "eks_rt_assoc_b" {
  subnet_id      = aws_subnet.eks_subnet_b.id
  route_table_id = aws_route_table.eks_rt.id
}

data "aws_caller_identity" "me" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_eks_deploy" {
  name = "${local.prefix}github-actions-eks-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:Duna-Devo/Cloud-devops-portfolio:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_eks_deploy" {
  name = "ecr-push-and-eks-describe"
  role = aws_iam_role.github_eks_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:us-east-1:${data.aws_caller_identity.me.account_id}:repository/stage5-app"
      },
      {
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = aws_eks_cluster.main.arn
      }
    ]
  })
}

resource "aws_eks_access_entry" "github" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_eks_deploy.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_eks_deploy.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["default"]
  }

  depends_on = [aws_eks_access_entry.github]
}

resource "aws_subnet" "eks_private_a" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)
  availability_zone = "us-east-1a"
  tags = {
    Name                              = "${local.prefix}eks-private-a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "eks_private_b" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 4)
  availability_zone = "us-east-1b"
  tags = {
    Name                              = "${local.prefix}eks-private-b"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.prefix}eks-nat-eip" }
}

resource "aws_nat_gateway" "eks_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.eks_subnet_a.id
  tags          = { Name = "${local.prefix}eks-nat" }

  depends_on = [aws_internet_gateway.eks_igw]
}

resource "aws_route_table" "eks_private_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat.id
  }

  tags = { Name = "${local.prefix}eks-private-rt" }
}

resource "aws_route_table_association" "eks_private_assoc_a" {
  subnet_id      = aws_subnet.eks_private_a.id
  route_table_id = aws_route_table.eks_private_rt.id
}

resource "aws_route_table_association" "eks_private_assoc_b" {
  subnet_id      = aws_subnet.eks_private_b.id
  route_table_id = aws_route_table.eks_private_rt.id
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "lb_controller" {
  name = "${local.prefix}eks-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "lb_controller" {
  name   = "${local.prefix}eks-lb-controller-policy"
  policy = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

variable "domain_name" {
  description = "Domain for the app, e.g. app.example.com. Must be in a Route 53 hosted zone you own."
  type        = string
}

variable "hosted_zone_name" {
  description = "Route 53 hosted zone, e.g. example.com"
  type        = string
}

data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "app" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

output "certificate_arn" {
  value = aws_acm_certificate_validation.app.certificate_arn
}

variable "alert_email" {
  description = "Email address that receives alarm notifications"
  type        = string
}

resource "aws_sns_topic" "alerts" {
  name = "${local.prefix}eks-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name          = "${local.prefix}eks-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Average node CPU above 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  }
}

resource "aws_iam_role" "tf_plan" {
  count = var.environment == "production" ? 1 : 0
  name  = "github-actions-tf-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:Duna-Devo/Cloud-devops-portfolio:pull_request"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  count      = var.environment == "production" ? 1 : 0
  role       = aws_iam_role.tf_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "tf_plan_state" {
  count = var.environment == "production" ? 1 : 0
  name  = "read-terraform-state"
  role  = aws_iam_role.tf_plan[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::duna-eks-tfstate"
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::duna-eks-tfstate/*"
      }
    ]
  })
}

resource "aws_iam_role" "tf_apply" {
  count = var.environment == "production" ? 1 : 0
  name  = "github-actions-tf-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:Duna-Devo/Cloud-devops-portfolio:environment:production"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "tf_apply_admin" {
  count      = var.environment == "production" ? 1 : 0
  role       = aws_iam_role.tf_apply[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

variable "environment" {
  description = "production or staging"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Use 10.2.0.0/16 for staging."
  type        = string
  default     = "10.1.0.0/16"
}

locals {
  prefix = var.environment == "production" ? "" : "${var.environment}-"
}
