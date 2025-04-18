#------------------------------
# IAM Role for Lambda Execution
#------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

#------------------------------
# Attach Basic Execution Role for Logs
#------------------------------
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#------------------------------
# Lambda Function (ZIP package)
#------------------------------
resource "aws_lambda_function" "admin_api" {
  function_name = "admin-api"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "admin_api.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  filename      = "lambda_deploy_package.zip"
  source_code_hash = filebase64sha256("lambda_deploy_package.zip")
}

#------------------------------
# Create HTTP API Gateway
#------------------------------
resource "aws_apigatewayv2_api" "admin_api" {
  name          = "admin-api"
  protocol_type = "HTTP"

  lifecycle {
    prevent_destroy = true
  }
}

#------------------------------
# Create Lambda integration
#------------------------------
resource "aws_apigatewayv2_integration" "admin_api" {
  api_id                 = aws_apigatewayv2_api.admin_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.admin_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

#------------------------------
# Define route for GET /admin-api/users
#------------------------------
resource "aws_apigatewayv2_route" "admin_api_route" {
  api_id    = aws_apigatewayv2_api.admin_api.id
  route_key = "GET /admin-api/users"
  target    = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
}

#------------------------------
# Deploy the API
#------------------------------
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.admin_api.id
  name        = "prod"
  auto_deploy = true
}

#------------------------------
# Lambda permission for API Gateway
#------------------------------
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke-${aws_apigatewayv2_api.admin_api.id}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.admin_api.execution_arn}/*/*"
}
