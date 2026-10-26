output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}
