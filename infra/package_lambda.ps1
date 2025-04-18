$zipPath = "lambda_deploy_package.zip"
$tempDir = "lambda_build"

# Clean up old files
Remove-Item -Recurse -Force $tempDir, $zipPath -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempDir

# Install dependencies
pip install -r requirements.txt -t $tempDir

# Copy source files
Copy-Item -Path "lambdas/admin_api.py" -Destination $tempDir
Copy-Item -Recurse -Path "admin" -Destination "$tempDir/admin"

# Create ZIP
Compress-Archive -Path "$tempDir/*" -DestinationPath $zipPath

Write-Host "✅ Lambda deployment package created: $zipPath"
