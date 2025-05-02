# deploy_validator.ps1

$ErrorActionPreference = "Stop"

# Paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Dockerfile content (inline definition)
$dockerfileContent = @"
FROM public.ecr.aws/lambda/python:3.11

COPY auth0_validator.py \${LAMBDA_TASK_ROOT}
RUN pip install PyJWT --target "\${LAMBDA_TASK_ROOT}"
"@

# Write Dockerfile
$dockerfilePath = Join-Path $scriptDir "Dockerfile"
$dockerfileContent | Set-Content -Path $dockerfilePath -Encoding UTF8

# Build and run Docker image to zip contents
docker build -t auth0-jwt-validator $scriptDir
docker run --rm -v "${scriptDir}:/output" auth0-jwt-validator powershell -Command `
    "Compress-Archive -Path * -DestinationPath /output/auth0_validator.zip"

# Cleanup
Remove-Item $dockerfilePath

Write-Host "✅ auth0_validator.zip created successfully in $scriptDir"
