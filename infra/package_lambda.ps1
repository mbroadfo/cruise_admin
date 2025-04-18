$zipPath = "lambda_deploy_package.zip"

# Remove existing zip if present
if (Test-Path $zipPath) {
    Remove-Item $zipPath
}

# Recreate clean structure in temp
$tempDir = "temp_lambda_package"
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Copy files
Copy-Item ./admin -Destination $tempDir/admin -Recurse
Copy-Item ./lambdas/admin_api.py -Destination $tempDir
Copy-Item ./requirements.txt -Destination $tempDir

# Zip from root of temp
Compress-Archive -Path "$tempDir/*" -DestinationPath $zipPath

# Clean up
Remove-Item -Recurse -Force $tempDir

Write-Host "✅ Lambda deployment package created: $zipPath"
