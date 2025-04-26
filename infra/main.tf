#------------------------------------------
# Data Sources
#------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_ecr_repository" "repo" {
  name = var.ecr_repo_name
}

#------------------------------------------
# Locals
#------------------------------------------
locals {
  image_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.ecr_repo_name}:${var.image_tag}"
}

#------------------------------------------
# ECR Repository (managed)
#------------------------------------------
resource "aws_ecr_repository" "repo" {
  name = var.app_name
}

resource "aws_ecr_repository_policy" "repo_policy" {
  repository = aws_ecr_repository.repo.name
  policy     = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid    = "AllowLambdaPull",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    }]
  })
}

#------------------------------------------
# IAM Role and Lambda Function
#------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name}-lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

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

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#------------------------------------------
# CloudWatch Log Groups
#------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.app_name}"
  retention_in_days = 7

  lifecycle { prevent_destroy = true }
}

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/${var.app_name}-access"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_resource_policy" "apigateway" {
  policy_name = "APIGatewayLogsPolicy"
  policy_document = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "apigateway.amazonaws.com" },
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"],
      Resource  = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/${var.app_name}-access:*"
    }]
  })
}

#------------------------------------------
# API Gateway
#------------------------------------------
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.app_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [
      "http://localhost:4173",
      "http://localhost:5173",
      "https://da389rkfiajdk.cloudfront.net"
    ]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.jwt_auth.id
}

resource "aws_apigatewayv2_authorizer" "jwt_auth" {
  name               = "${var.app_name}-jwt-authorizer"
  api_id             = aws_apigatewayv2_api.api.id
  authorizer_type    = "JWT"
  identity_sources   = ["$request.header.Authorization"]
  jwt_configuration {
    audience = ["https://cruise-admin-api"]
    issuer   = "https://${var.auth0_domain}/"
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id = aws_apigatewayv2_api.api.id
  name   = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId",
      ip             = "$context.identity.sourceIp",
      caller         = "$context.identity.caller",
      user           = "$context.identity.user",
      requestTime    = "$context.requestTime",
      httpMethod     = "$context.httpMethod",
      resourcePath   = "$context.resourcePath",
      status         = "$context.status",
      protocol       = "$context.protocol",
      responseLength = "$context.responseLength",
      errorMessage   = "$context.error.message"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    logging_level             = "INFO"
    data_trace_enabled        = true
  }
}

#------------------------------------------
# API Gateway to Lambda Permission
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

#------------------------------------------
# SecretsManager Policy
#------------------------------------------
resource "aws_iam_policy" "lambda_secrets_access" {
  name        = "${var.app_name}-secrets-access"
  description = "Allow Lambda to access secrets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["secretsmanager:GetSecretValue"],
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:cruise-finder-secrets*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_secrets_access.arn
}

#------------------------------------------
# API Gateway Account Settings
#------------------------------------------
resource "aws_api_gateway_account" "account" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch_role.arn
}

resource "aws_iam_role" "apigateway_cloudwatch_role" {
  name = "${var.app_name}-apigateway-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "apigateway.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "apigateway_cloudwatch_policy" {
  name = "${var.app_name}-apigateway-logs-policy"
  role = aws_iam_role.apigateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      Resource = "*"
    }]
  })
}
