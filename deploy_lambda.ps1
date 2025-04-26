# Set buildkit off (legacy builder needed for Lambda ECR compatibility)
$env:DOCKER_BUILDKIT=0

# Generate a timestamped tag
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$imageTag = "v$timestamp"

# Build Docker image for Linux/amd64
docker build --platform linux/amd64 -t cruise-admin-api:$imageTag .

# Retag for ECR
docker tag cruise-admin-api:$imageTag 491696534851.dkr.ecr.us-west-2.amazonaws.com/cruise-admin-api:$imageTag

# Login to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 491696534851.dkr.ecr.us-west-2.amazonaws.com

# Push to ECR
docker push 491696534851.dkr.ecr.us-west-2.amazonaws.com/cruise-admin-api:$imageTag

# Output the full image URI for Terraform input
Write-Host "`nFull ECR Image URI:"
Write-Host "491696534851.dkr.ecr.us-west-2.amazonaws.com/cruise-admin-api:$imageTag"
