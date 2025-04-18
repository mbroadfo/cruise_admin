$zipPath = "lambda_deploy_package.zip"
$buildDir = "build_lambda"

# Clean build directory
if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
New-Item -ItemType Directory -Path $buildDir | Out-Null

# Copy source files
Copy-Item ../lambdas/admin_api.py $buildDir/
Copy-Item ../requirements.txt $buildDir/
Copy-Item ../admin -Recurse -Destination $buildDir/admin

# Remove existing zip if present
if (Test-Path $zipPath) {
    Remove-Item $zipPath
}

# Create the zip file
Compress-Archive -Path "$buildDir/*" -DestinationPath $zipPath

Write-Host "✅ Lambda deployment package created: $zipPath"
