variable "vaultwarden_admin_hash" {
  description = "Argon hash of the password to access the admin panel"
}

variable "gateway_domain" {
  description = "The domain that shall be used for API Gateway, i.e. where vaultwarden will be accessible after"
}

variable "aws_region" {
  description = "The AWS region to deploy vaultwarden-serverless in"
}