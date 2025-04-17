$zipPath = "lambda_deploy_package.zip"
$repoRoot = Resolve-Path "$PSScriptRoot/.."
$sourceFiles = @(
    "$repoRoot/lambdas/admin_api.py",
    "$repoRoot/admin/aws_secrets.py",
    "$repoRoot/requirements.txt"
)

# Remove existing zip if present
if (Test-Path $zipPath) {
    Remove-Item $zipPath
}

# Create the zip file
Compress-Archive -Path $sourceFiles -DestinationPath $zipPath

Write-Host "✅ Lambda deployment package created: $zipPath"
