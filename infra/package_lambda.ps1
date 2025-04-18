$zipPath = "lambda_deploy_package.zip"
$tempDir = "lambda_package"

# Clean up old package and temp directory
if (Test-Path $zipPath) { Remove-Item $zipPath }
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }

# Create temp directory
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Install Python dependencies
pip install requests -t $tempDir

# Copy Python source files
Copy-Item -Path "./lambdas/admin_api.py" -Destination $tempDir
Copy-Item -Path "./admin" -Recurse -Destination "$tempDir/admin"

# Create the zip package
Compress-Archive -Path "$tempDir/*" -DestinationPath $zipPath

Write-Host "✅ Lambda deployment package created: $zipPath"
