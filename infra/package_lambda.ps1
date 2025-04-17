$zipPath = "lambda_deploy_package.zip"
$sourceFiles = @(
    "lambdas/admin_api.py",
    "admin",
    "requirements.txt"
)

# Remove existing zip if present
if (Test-Path $zipPath) {
    Remove-Item $zipPath
}

# Create the zip file
Compress-Archive -Path $sourceFiles -DestinationPath $zipPath

Write-Host "✅ Lambda deployment package created: $zipPath"
