#------------------------------------------
# Data Sources
#------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------
# Locals
#------------------------------------------
locals {
  image_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.ecr_repo_name}:${var.image_tag}"
}

#------------------------------------------
# ECR Repository
#------------------------------------------
resource "aws_ecr_repository" "repo" {
  name = var.ecr_repo_name
}

#------------------------------------------
# ECR Repository policy
#------------------------------------------
resource "aws_ecr_repository_policy" "repo_policy" {
  repository = aws_ecr_repository.repo.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowLambdaPull",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    }]
  })
}

#------------------------------------------
# IAM Role and Policies
#------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name}-lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

#------------------------------------------
# IAM Policy - Lambda logs
#------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#------------------------------------------
# IAM Policy - Lambda secrets access
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

#------------------------------------------
# IAM Role - Lambda secrets exec
#------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_secrets_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_secrets_access.arn
}

#------------------------------------------
# Lambda Function
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

  depends_on = [aws_ecr_repository.repo, aws_ecr_repository_policy.repo_policy]
}

#------------------------------------------
# API Gateway REST API
#------------------------------------------
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.app_name}-api"
  description = "Cruise Admin REST API"
}

#------------------------------------------
# API Gateway - Admin API
#------------------------------------------
resource "aws_api_gateway_resource" "admin_api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "admin-api"
}

#------------------------------------------
# API Gateway - users route
#------------------------------------------
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.admin_api.id
  path_part   = "users"
}

#------------------------------------------
# API Gateway - GET method response
#------------------------------------------
resource "aws_api_gateway_method_response" "get_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.get_users.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

#------------------------------------------
# API Gateway - users options route
#------------------------------------------
resource "aws_api_gateway_method" "options_users" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

#------------------------------------------
# API Gateway - options integration
#------------------------------------------
resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.options_users.http_method

  type                 = "MOCK"
  request_templates    = { "application/json" = "{\"statusCode\": 200}" }
}

#------------------------------------------
# API Gateway - options response
#------------------------------------------
resource "aws_api_gateway_method_response" "options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.options_users.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

#------------------------------------------
# API Gateway - options integration response
#------------------------------------------
resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.options_users.http_method
  status_code = aws_api_gateway_method_response.options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Authorization,Content-Type'",
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,DELETE'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

#-----------------------------------------------
#  API Gateway - GET users method
#-----------------------------------------------
resource "aws_api_gateway_method" "get_users" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "NONE"  # (or "AWS_IAM" / "COGNITO_USER_POOLS" / etc. if you want auth here later)
}

#-----------------------------------------------
#  API Gateway - POST user method
#-----------------------------------------------
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "NONE"
}

#------------------------------------------
# API Gateway - POST method integration
#------------------------------------------
resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.app.invoke_arn
}

#------------------------------------------
# API Gateway - POST method response
#------------------------------------------
resource "aws_api_gateway_method_response" "post_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

#-----------------------------------------------
#  API Gateway - DELETE user method
#-----------------------------------------------
resource "aws_api_gateway_method" "delete_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "DELETE"
  authorization = "NONE"
}

#------------------------------------------
# API Gateway - DELETE method integration
#------------------------------------------
resource "aws_api_gateway_integration" "delete_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.delete_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.app.invoke_arn
}

#------------------------------------------
# API Gateway - DELETE Response
#------------------------------------------
resource "aws_api_gateway_method_response" "delete_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.delete_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

#-----------------------------------------------
# API Gateway - resource policy
#-----------------------------------------------
resource "aws_api_gateway_rest_api_policy" "api_policy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = "*",
      Action = "execute-api:Invoke",
      Resource = "${aws_api_gateway_rest_api.api.execution_arn}/*",
      Condition = {
        IpAddress = {
          "aws:SourceIp" = var.allowed_ips  # Define in variables.tf
        }
      }
    }]
  })
}

#-----------------------------------------------
#  API Gateway - Lambda Integration
#-----------------------------------------------
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.get_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"  # Must be PROXY to pass headers
  uri                     = aws_lambda_function.app.invoke_arn
}

#------------------------------------------
# Lambda permission - allow API Gateway POST
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw_post" {
  statement_id  = "AllowAPIGatewayInvokePost"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/POST/admin-api/users"
}

#------------------------------------------
# Lambda permission - allow API Gateway DELETE
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw_delete" {
  statement_id  = "AllowAPIGatewayInvokeDelete"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/DELETE/admin-api/users"
}

#------------------------------------------
# API Gateway - DEPLOYMENT TRIGGER
#------------------------------------------
resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      timestamp(),
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_method.get_users.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_method.delete_method.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------
# API Gateway - prod state & log settings
#------------------------------------------
resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id

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

  xray_tracing_enabled = true

  tags = {}
}

#------------------------------------------
# CloudWatch Log Group for API Gateway
#------------------------------------------
resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/${var.app_name}-access"
  retention_in_days = 7
}

#------------------------------------------
# CloudWatch Log Group for Lambda
#------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.app_name}"
  retention_in_days = 7
  lifecycle {
    prevent_destroy = true
  }
}

#------------------------------------------
# CloudWatch Logging on API Gateway Account
#------------------------------------------
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch_role.arn
}

#------------------------------------------
# IAM Role - API Gateway Cloudwatch Role
#------------------------------------------
resource "aws_iam_role" "apigateway_cloudwatch_role" {
  name = "${var.app_name}-apigw-cloudwatch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "apigateway.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

#------------------------------------------
# IAM Policy - API Gateway Cloudwatch role policy
#------------------------------------------
resource "aws_iam_role_policy" "apigateway_cloudwatch_role_policy" {
  name = "${var.app_name}-apigw-cloudwatch-policy"
  role = aws_iam_role.apigateway_cloudwatch_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
        ],
        Resource = "*"
      }
    ]
  })
}
