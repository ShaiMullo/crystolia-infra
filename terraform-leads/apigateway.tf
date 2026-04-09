# -----------------------------------------------------------------------------
# API Gateway HTTP API — Leads Endpoint
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "leads" {
  name          = "crystolia-leads-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 86400
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.leads.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "leads" {
  api_id                 = aws_apigatewayv2_api.leads.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.leads.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_lead" {
  api_id    = aws_apigatewayv2_api.leads.id
  route_key = "POST /lead"
  target    = "integrations/${aws_apigatewayv2_integration.leads.id}"
}
