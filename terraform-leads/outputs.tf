output "api_url" {
  description = "API Gateway base URL (POST /lead)"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "leads_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.leads.name
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.leads.function_name
}
