output "organization_id" {
  value = aws_organizations_organization.main.id
}

output "sandbox_account_id" {
  value = aws_organizations_account.sandbox.id
}
