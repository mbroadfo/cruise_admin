$zipPath = "lambda_deploy_package.zip"
$tempDir = "lambda_package"

# Clean up old package and temp directory
if (Test-Path $zipPath) { Remove-Item $zipPath }
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }

# Create temp directory
New-Item -ItemType Directory -Path $tempDir | Out-Null

# ✅ Install dependencies into the temp directory
pip install -r requirements.txt -t $tempDir

# Copy lambda code
Copy-Item -Path "./lambdas/admin_api.py" -Destination $tempDir
Copy-Item -Path "./admin" -Recurse -Destination "$tempDir/admin"

# ✅ Zip the entire contents (recursively)
Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath

Write-Host "✅ Lambda deployment package created: $zipPath"

# 🕵️ Expand the zip and list its contents for verification
$checkPath = "check_zip"
if (Test-Path $checkPath) { Remove-Item $checkPath -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $checkPath
Get-ChildItem $checkPath
