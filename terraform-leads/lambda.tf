# -----------------------------------------------------------------------------
# Lambda Function — Lead Submission
# -----------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../../crystolia-app/leads-api/index.mjs"
  output_path = "${path.module}/lambda/function.zip"
}

resource "aws_lambda_function" "leads" {
  function_name    = "crystolia-leads"
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  role             = aws_iam_role.lambda.arn
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME      = aws_dynamodb_table.leads.name
      ALLOWED_ORIGINS = join(",", var.allowed_origins)
    }
  }
}

# Allow API Gateway to invoke this function
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.leads.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.leads.execution_arn}/*/*"
}
