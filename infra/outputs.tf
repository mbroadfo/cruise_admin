output "api_gateway_url" {
  description = "URL for the deployed API Gateway"
  value       = aws_apigatewayv2_api.api.api_endpoint
}