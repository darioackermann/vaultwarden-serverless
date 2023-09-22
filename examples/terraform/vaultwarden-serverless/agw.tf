data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_apigatewayv2_api" "vaultwarden" {
  name          = "vaultwarden"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.vaultwarden.id
  auto_deploy = true
  name        = "$default"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.vaultwarden.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_handler.id}"
}

resource "aws_apigatewayv2_route" "exporter" {
  api_id    = aws_apigatewayv2_api.vaultwarden.id
  route_key = "ANY /tools/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.export_handler.id}"
}

resource "aws_apigatewayv2_route" "exporter_alt" {
  api_id    = aws_apigatewayv2_api.vaultwarden.id
  route_key = "ANY /tools"
  target    = "integrations/${aws_apigatewayv2_integration.export_handler.id}"
}

resource "aws_apigatewayv2_integration" "export_handler" {
  api_id                 = aws_apigatewayv2_api.vaultwarden.id
  integration_type       = "AWS_PROXY"
  payload_format_version = "2.0"
  integration_uri        = aws_lambda_function.exporter.invoke_arn
}

resource "aws_apigatewayv2_integration" "lambda_handler" {
  api_id                 = aws_apigatewayv2_api.vaultwarden.id
  integration_type       = "AWS_PROXY"
  payload_format_version = "2.0"
  integration_uri        = aws_lambda_function.vaultwarden_function.invoke_arn
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vaultwarden_function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.vaultwarden.execution_arn}/*/*"
}

resource "aws_lambda_permission" "for_exporter" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.exporter.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.vaultwarden.execution_arn}/*/*"
}

resource "aws_apigatewayv2_domain_name" "domainname" {
  domain_name = var.gateway_domain
  domain_name_configuration {
    certificate_arn = aws_acm_certificate.main_domain.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
  depends_on = [aws_acm_certificate_validation.main_domain]
}

resource "aws_apigatewayv2_api_mapping" "mapping" {
  api_id      = aws_apigatewayv2_api.vaultwarden.id
  domain_name = aws_apigatewayv2_domain_name.domainname.id
  stage       = aws_apigatewayv2_stage.stage.id
}

output "api_gateway_cname_target" {
  value = aws_apigatewayv2_domain_name.domainname.domain_name_configuration[0].target_domain_name
}

output "api_gateway_invocation_url" {
  value = aws_apigatewayv2_stage.stage.invoke_url
}