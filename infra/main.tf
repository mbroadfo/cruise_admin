#------------------------------------------
# ECR Repository
#------------------------------------------
resource "aws_ecr_repository" "repo" {
  name = var.app_name
}

#------------------------------------------
# ECR Repository Policy to Allow Lambda Pull
#------------------------------------------
resource "aws_ecr_repository_policy" "repo_policy" {
  repository = aws_ecr_repository.repo.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowLambdaPull",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

#------------------------------------------
# IAM Role for Lambda Execution
#------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

#------------------------------------------
# Attach basic execution policy to Lambda
#------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#------------------------------------------
# Construct full image URI
#------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_ecr_repository" "repo" {
  name = var.ecr_repo_name
}

locals {
  image_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.ecr_repo_name}:${var.image_tag}"
}

#------------------------------------------
# Lambda Function (using dynamic image URI)
#------------------------------------------
resource "aws_lambda_function" "app" {
  function_name = var.app_name
  package_type  = "Image"
  image_uri     = local.image_uri
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 30
  memory_size   = 512

  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [
    aws_ecr_repository.repo,
    aws_ecr_repository_policy.repo_policy
  ]
}


#------------------------------------------
# API Gateway HTTP API
#------------------------------------------
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.app_name}-api"
  protocol_type = "HTTP"
}

#------------------------------------------
# API Gateway Integration
#------------------------------------------
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "2.0"
}

#------------------------------------------
# API Gateway Route (default)
#------------------------------------------
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

#------------------------------------------
# API Gateway Stage
#------------------------------------------
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

#------------------------------------------
# Lambda Permission to be Invoked by API Gateway
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
