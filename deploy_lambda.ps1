# Set up some variables
$ecrRepo = "491696534851.dkr.ecr.us-west-2.amazonaws.com/list-users"
$ecrArn = "491696534851.dkr.ecr.us-west-2.amazonaws.com"
$imageName = "list-users-lambda"
$tag = "latest"

docker logout $ecrRepo
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ecrArn

Write-Host "🔧 Building Docker image..."
docker build -f Dockerfile.lambda -t $imageName ./
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Docker build failed. Aborting deployment."
    exit 1
}

Write-Host "🔁 Tagging image..."
docker tag "${imageName}:${tag}" "${ecrRepo}:${tag}"
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Docker tag failed. Aborting deployment."
    exit 1
}

Write-Host "🔐 Logging into ECR..."
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 491696534851.dkr.ecr.us-west-2.amazonaws.com
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ ECR login failed. Aborting deployment."
    exit 1
}

Start-Sleep -Seconds 5  # Let ECR settle before pushing

Write-Host "📤 Pushing image to ECR..."

$maxRetries = 5
$retryDelay = 5
$attempt = 0
$success = $false

while (-not $success -and $attempt -lt $maxRetries) {
    $attempt++
    docker push "${ecrRepo}:${tag}"
    if ($LASTEXITCODE -eq 0) {
        $success = $true
        Write-Host "✅ Image pushed successfully after $attempt attempt(s)."
    } else {
        Write-Warning "⚠️ Push failed (attempt $attempt). Retrying in $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
    }
}

if (-not $success) {
    Write-Error "❌ Docker push failed after $maxRetries attempts. Aborting deployment."
    exit 1
}

Write-Host "✅ Deployment complete!"
