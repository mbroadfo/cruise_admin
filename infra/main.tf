#====================================== SETUP (data & locals) ===================================================
# Core Terraform configuration and shared variables
#================================================================================================================

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

#===================================== ECR ======================================================================
# Docker image repository for Lambda container images
#================================================================================================================

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

#======================================== IAM ===================================================================
# AWS Identity & Access Management roles and policies
#================================================================================================================

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
# API Gateway - IAM Role for Lambda Authorizer
#------------------------------------------
resource "aws_iam_role" "api_gateway_auth_lambda" {
  name = "lambda-jwt-auth-role"

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
# API Gateway - IAM Role Policy Invoke Auth Lambda
#------------------------------------------
resource "aws_iam_role_policy" "invoke_auth_lambda" {
  name = "invoke-auth0-validator"
  role = aws_iam_role.api_gateway_auth_lambda.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "lambda:InvokeFunction",
      Resource = "arn:aws:lambda:us-west-2:491696534851:function:auth0-jwt-validator"
    }]
  })
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

#===================================== LAMBDA ===================================================================
# AWS Lambda function configurations
#================================================================================================================
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

  image_config {
    command = ["app.main.lambda_handler"]  # 👈 Custom handler
  }
  lifecycle {
    ignore_changes = [image_uri]  # Prevent Terraform from overwriting during CI/CD
  }

  depends_on = [aws_ecr_repository.repo, aws_ecr_repository_policy.repo_policy]
}

#------------------------------------------
# Auth0 JWT Validator Lambda Function
#------------------------------------------
resource "aws_lambda_function" "auth0_validator" {
  function_name = "auth0-jwt-validator"
  handler       = "auth0_validator.handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "./auth0_validator.zip"
  source_code_hash = filebase64sha256("./auth0_validator.zip")
  timeout       = 5
  memory_size   = 128
}

#==================================== LAMBDA PERMISSIONS ========================================================
# Cross-service permissions allowing API Gateway to invoke Lambda functions
#================================================================================================================

#------------------------------------------
# Lambda permission - allow API Gateway GET
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw_get" {
  statement_id  = "AllowAPIGatewayInvokeGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/admin-api/users"
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
# API Gateway - Lambda Permission
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/*/*"
}

#------------------------------------------
# API Gateway - Lambda Permission Invoke Validator
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw_invoke_validator" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth0_validator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*"
}

#------------------------------------------
# API Gateway - Lambda Permissions for PATCH
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw_patch_favorites" {
  statement_id  = "AllowAPIGatewayInvokePatchFavorites"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/PATCH/admin-api/user/favorites"
}

#------------------------------------------
# API Gateway - Lambda Permissions for Get User
#------------------------------------------
resource "aws_lambda_permission" "allow_apigw_get_user" {
  statement_id  = "AllowAPIGatewayInvokeGetUser"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/admin-api/user"
}

#================================ API GATEWAY - Core API Configuration ==========================================
# Root API setup including policy controls and base configuration
#================================================================================================================

#------------------------------------------
# API Gateway REST API
#------------------------------------------
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.app_name}-api"
  description = "Cruise Admin REST API"
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

#================================ API GATEWAY - Resource Structure ==============================================
# Path routing definitions (admin-api/users endpoints and hierarchy)
#================================================================================================================

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
# API Gateway - user/favorites PATCH route
#------------------------------------------
resource "aws_api_gateway_resource" "user_favorites" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.admin_api.id
  path_part   = "user"
}

#------------------------------------------
# API Gateway - /admin-api/user/favorites sub-resource
#------------------------------------------
resource "aws_api_gateway_resource" "user_favorites_path" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.user_favorites.id
  path_part   = "favorites"
}

#================================ API GATEWAY - Method Definitions ==============================================
# HTTP verb implementations with Auth0 JWT authorization requirements
#================================================================================================================

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
# API Gateway - GET users method
#------------------------------------------
resource "aws_api_gateway_method" "get_users" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.auth0_lambda_authorizer.id 
}


#------------------------------------------
# API Gateway - POST user method
#------------------------------------------
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.auth0_lambda_authorizer.id
}

#------------------------------------------
# API Gateway - DELETE user method
#------------------------------------------
resource "aws_api_gateway_method" "delete_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "DELETE"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.auth0_lambda_authorizer.id
}

#------------------------------------------
# API Gateway - PATCH user favorites method
#------------------------------------------
resource "aws_api_gateway_method" "patch_favorites" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_favorites_path.id
  http_method   = "PATCH"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.auth0_lambda_authorizer.id
}

#------------------------------------------
# API Gateway - OPTIONS user favorites method
#------------------------------------------
resource "aws_api_gateway_method" "options_user_favorites" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_favorites.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_user_favorites_path" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_favorites_path.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_user" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_favorites.id  # /admin-api/user
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.auth0_lambda_authorizer.id
}

#================================ API GATEWAY - Method Responses ================================================
# Status code declarations and CORS header configurations
#================================================================================================================

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

#------------------------------------------
# API Gateway - PATCH favorites method response
#------------------------------------------
resource "aws_api_gateway_method_response" "patch_favorites_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites_path.id 
  http_method = aws_api_gateway_method.patch_favorites.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

#------------------------------------------
# API Gateway - OPTIONS user favorites method response
#------------------------------------------
resource "aws_api_gateway_method_response" "options_user_favorites_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites.id
  http_method = aws_api_gateway_method.options_user_favorites.http_method
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

resource "aws_api_gateway_method_response" "options_user_favorites_path_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites_path.id
  http_method = aws_api_gateway_method.options_user_favorites_path.http_method
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

resource "aws_api_gateway_method_response" "get_user_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites.id
  http_method = aws_api_gateway_method.get_user.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true,
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

#================================ API GATEWAY - Integrations ====================================================
# Lambda proxy connections and MOCK implementations for OPTIONS
#================================================================================================================

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

#-----------------------------------------------
#  API Gateway - Lambda Integration
#-----------------------------------------------
resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.get_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"  # Must be PROXY to pass headers
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.app.arn}/invocations"
}

#------------------------------------------
# API Gateway - POST integration
#------------------------------------------
resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.app.arn}/invocations"
}

#------------------------------------------
# API Gateway - DELETE integration
#------------------------------------------
resource "aws_api_gateway_integration" "delete_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.delete_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.app.arn}/invocations"
}

#------------------------------------------
# API Gateway - PATCH favorites integration
#------------------------------------------
resource "aws_api_gateway_integration" "patch_favorites_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.user_favorites_path.id
  http_method             = aws_api_gateway_method.patch_favorites.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.app.arn}/invocations"
}

#------------------------------------------
# API Gateway - OPTIONS user favorites integration
#------------------------------------------
resource "aws_api_gateway_integration" "options_user_favorites_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites.id
  http_method = aws_api_gateway_method.options_user_favorites.http_method

  type              = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "options_user_favorites_path_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites_path.id
  http_method = aws_api_gateway_method.options_user_favorites_path.http_method

  type              = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "get_user_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.user_favorites.id
  http_method             = aws_api_gateway_method.get_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.app.arn}/invocations"
}

#================================ API GATEWAY - Integration Responses ===========================================
# Response header transformations and CORS permission mappings
#================================================================================================================

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

#------------------------------------------
# API Gateway = GET Integration Response
#------------------------------------------
resource "aws_api_gateway_integration_response" "get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.get_users.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,DELETE,OPTIONS'"
  }

  depends_on = [aws_api_gateway_method_response.get_response]
}

#------------------------------------------
# API Gateway = POST Integration Response
#------------------------------------------
resource "aws_api_gateway_integration_response" "post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,DELETE,OPTIONS'"
  }

  depends_on = [aws_api_gateway_method_response.post_response]
}

#------------------------------------------
# API Gateway = DELETE Integration Response
#------------------------------------------
resource "aws_api_gateway_integration_response" "delete_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.delete_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,DELETE,OPTIONS'"
  }

  depends_on = [aws_api_gateway_method_response.delete_response]
}

#------------------------------------------
# API Gateway = PATCH favorites Integration Response
#------------------------------------------
resource "aws_api_gateway_integration_response" "patch_favorites_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites_path.id
  http_method = aws_api_gateway_method.patch_favorites.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'",
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,DELETE,OPTIONS,PATCH'"
  }

  depends_on = [aws_api_gateway_method_response.patch_favorites_response]
}

#------------------------------------------
# API Gateway - OPTIONS user favorites integration response
#------------------------------------------
resource "aws_api_gateway_integration_response" "options_user_favorites_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites.id
  http_method = aws_api_gateway_method.options_user_favorites.http_method
  status_code = aws_api_gateway_method_response.options_user_favorites_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,DELETE,OPTIONS,PATCH'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "options_user_favorites_path_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites_path.id
  http_method = aws_api_gateway_method.options_user_favorites_path.http_method
  status_code = aws_api_gateway_method_response.options_user_favorites_path_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,DELETE,OPTIONS,PATCH'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "get_user_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_favorites.id
  http_method = aws_api_gateway_method.get_user.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'",
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
  }

  depends_on = [aws_api_gateway_method_response.get_user_response]
}

#================================ API GATEWAY - Authorizer  =====================================================
# Auth0 token validation service and credential configuration
#================================================================================================================

#------------------------------------------
# API Gateway - Lambda TOKEN Authorizer (Auth0 Validator)
#------------------------------------------
resource "aws_api_gateway_authorizer" "auth0_lambda_authorizer" {
  name                         = "auth0-lambda-authorizer"
  rest_api_id                  = aws_api_gateway_rest_api.api.id
  authorizer_uri                = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.auth0_validator.arn}/invocations"
  authorizer_result_ttl_in_seconds = 300
  type                         = "TOKEN"
  identity_source              = "method.request.header.Authorization"
  authorizer_credentials       = aws_iam_role.api_gateway_auth_lambda.arn  
}

#================================= CLOUDWATCH ===================================================================
# Monitoring and logging resources
#================================================================================================================

#------------------------------------------
# CloudWatch Logging on API Gateway Account
#------------------------------------------
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch_role.arn
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
# CloudWatch Log Group for JWT Validtor
#------------------------------------------
resource "aws_cloudwatch_log_group" "auth0_validator_logs" {
  name              = "/aws/lambda/auth0-jwt-validator"
  retention_in_days = 7
  lifecycle {
    prevent_destroy = true
  }
}
#================================= DEPLOYMENT ===================================================================
# API Gateway stage deployment and logging setup
#================================================================================================================

#------------------------------------------
# API Gateway - DEPLOYMENT TRIGGER
#------------------------------------------
resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      timestamp(),
      aws_api_gateway_integration.get_integration.id,
      aws_api_gateway_integration.post_integration.id,
      aws_api_gateway_integration.delete_integration.id,
      aws_api_gateway_integration.patch_favorites_integration.id,
      aws_api_gateway_integration.options_integration.id,
      aws_api_gateway_integration.options_user_favorites_integration.id,
      aws_api_gateway_integration.options_user_favorites_path_integration.id,
      aws_api_gateway_integration.get_user_integration.id,

      aws_api_gateway_method.get_users.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_method.delete_method.id,
      aws_api_gateway_method.patch_favorites.id,
      aws_api_gateway_method.options_users.id,
      aws_api_gateway_method.options_user_favorites.id,
      aws_api_gateway_method.options_user_favorites_path.id,
      aws_api_gateway_method.get_user.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.get_integration,
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.delete_integration,
    aws_api_gateway_integration.patch_favorites_integration,
    aws_api_gateway_integration.get_user_integration,
    aws_api_gateway_method.get_users,
    aws_api_gateway_method.post_method,
    aws_api_gateway_method.delete_method,
    aws_api_gateway_method.patch_favorites,
    aws_api_gateway_method.get_user
  ]
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
      errorMessage   = "$context.error.message",
      integrationErrorMessage = "$context.integration.error"
    })
  }

  xray_tracing_enabled = true

  tags = {}
}
