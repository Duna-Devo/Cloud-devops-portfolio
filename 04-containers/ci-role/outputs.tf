output "deploy_role_arns" {
  value = { for env, role in aws_iam_role.deploy : env => role.arn }
}
