$ErrorActionPreference = "Stop"

# Ensure Docker Desktop is running
try {
    $dockerRunning = docker info > $null
    if (-not $dockerRunning) {
        Write-Host "Starting Docker Desktop..."
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        Start-Sleep -Seconds 10
        $dockerRunning = docker info -ErrorAction SilentlyContinue
        if (-not $dockerRunning) {
            Write-Error "Docker Desktop did not start successfully. Aborting."
            exit 1
        }
    }
} catch {
    Write-Host "Docker is not running. Attempting to start Docker Desktop..."
    Start-Process -FilePath "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10

    $retries = 12
    while ($retries -gt 0) {
        try {
            docker info > $null
            Write-Host "Docker is now running."
            break
        } catch {
            Start-Sleep -Seconds 5
            $retries--
        }
    }

    if ($retries -eq 0) {
        throw "Docker failed to start in time."
    }
}

# Paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $scriptDir "build"
$zipPath = Join-Path $scriptDir "auth0_validator.zip"

# Clean build dir
if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
New-Item -ItemType Directory -Path $buildDir | Out-Null

# Write Dockerfile
@"
FROM public.ecr.aws/lambda/python:3.11
WORKDIR /tmp/build
COPY auth0_validator.py .
RUN pip install "pyjwt[crypto]" --target .
CMD ["bash"]
"@ | Set-Content -Path "$scriptDir/Dockerfile"

# Build image and copy dependencies
docker build -t auth0-validator-builder $scriptDir
docker create --name temp-container auth0-validator-builder > $null
docker cp temp-container:/tmp/build/. $buildDir
docker rm temp-container > $null

# Cleanup Docker artifacts
Remove-Item "$scriptDir/Dockerfile"
docker image rm auth0-validator-builder > $null

# Create zip
if (Test-Path $zipPath) { Remove-Item $zipPath }
Compress-Archive -Path "$buildDir\*" -DestinationPath $zipPath

# Done
if (Test-Path $zipPath) {
    Write-Host "auth0_validator.zip created at $((Get-Item $zipPath).LastWriteTime)"
} else {
    Write-Error "Zip file was not created."
}
