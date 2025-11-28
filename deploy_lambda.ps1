# Deploy Lambda Function (ZIP-based deployment)
# This script builds the deployment package and uploads it to AWS Lambda

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Deploying cruise-admin-api to AWS Lambda" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 1: Build deployment package
Write-Host "`n[1/3] Building deployment package..." -ForegroundColor Yellow
python build_lambda.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

# Step 2: Upload to Lambda
Write-Host "`n[2/3] Uploading to Lambda..." -ForegroundColor Yellow
$env:AWS_PROFILE = "terraform"
aws lambda update-function-code `
    --function-name cruise-admin-api `
    --zip-file fileb://deployment.zip `
    --region us-west-2 `
    --output json | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Lambda upload failed!" -ForegroundColor Red
    exit 1
}

# Step 3: Wait for update to complete and verify
Write-Host "`n[3/3] Waiting for function update..." -ForegroundColor Yellow
aws lambda wait function-updated `
    --function-name cruise-admin-api `
    --region us-west-2

# Get updated function info
$functionInfo = aws lambda get-function-configuration `
    --function-name cruise-admin-api `
    --region us-west-2 `
    --query '{Runtime:Runtime, CodeSize:CodeSize, LastModified:LastModified, PackageType:PackageType}' | ConvertFrom-Json

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "✅ Deployment successful!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Runtime:       $($functionInfo.Runtime)"
Write-Host "Package Type:  $($functionInfo.PackageType)"
Write-Host "Code Size:     $([math]::Round($functionInfo.CodeSize / 1MB, 2)) MB"
Write-Host "Last Modified: $($functionInfo.LastModified)"
Write-Host "`nFunction URL: https://62rbm8zvak.execute-api.us-west-2.amazonaws.com/prod/admin-api/users"
