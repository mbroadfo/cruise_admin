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
