output "api_gateway_url" {
  description = "Invoke URL of API Gateway"
  value       = aws_api_gateway_stage.prod.invoke_url
}
