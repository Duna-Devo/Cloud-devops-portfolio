############################################
# Cognito: users sign in here and receive a signed token
############################################
resource "aws_cognito_user_pool" "main" {
  name                     = "${local.name}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"
  deletion_protection      = var.environment == "prod" ? "ACTIVE" : "INACTIVE"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# The "app" that signs users in (web or mobile frontend). No client secret:
# a browser or phone cannot keep one private.
resource "aws_cognito_user_pool_client" "app" {
  name         = "${local.name}-app"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"

  # SRP = password is never sent in clear text. ADMIN_USER_PASSWORD_AUTH is only
  # usable with IAM credentials that hold cognito-idp:AdminInitiateAuth, and is
  # what the pipeline's smoke test uses with a throwaway user.
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
  ]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
