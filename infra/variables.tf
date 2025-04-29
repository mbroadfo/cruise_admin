variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-west-2"
}

variable "app_name" {
  description = "Name for app resources"
  type        = string
  default     = "cruise-admin-api"
}

variable "ecr_repo_name" {
  description = "ECR Repository name"
  type        = string
  default     = "cruise-admin-api"
}

variable "image_tag" {
  description = "Image tag to deploy"
  type        = string
  default     = "latest"
}

variable "auth0_domain" {
  description = "Auth0 Domain (without https://)"
  type        = string
  default     = "dev-jdsnf3lqod8nxlnv.us.auth0.com"
}

variable "allowed_ips" {
  description = "List of IPs allowed to access the API"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Allow all by default (restrict for production)
}