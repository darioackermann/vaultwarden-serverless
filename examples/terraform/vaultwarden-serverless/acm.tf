resource "aws_acm_certificate" "main_domain" {
  domain_name       = var.gateway_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "main_domain" {
  certificate_arn = aws_acm_certificate.main_domain.arn
}