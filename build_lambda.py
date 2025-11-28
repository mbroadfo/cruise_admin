#!/usr/bin/env python3
"""
Build Lambda deployment package (ZIP format)

This script creates a deployment.zip file containing:
- Application code (app/ and admin/ directories)
- Python dependencies from requirements.txt
- Properly structured for AWS Lambda execution
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path
import zipfile


def clean_build_artifacts():
    """Remove previous build artifacts"""
    print("🧹 Cleaning previous build artifacts...")
    artifacts = ["deployment.zip", "package/"]
    for artifact in artifacts:
        path = Path(artifact)
        if path.is_file():
            path.unlink()
            print(f"   Removed {artifact}")
        elif path.is_dir():
            shutil.rmtree(path)
            print(f"   Removed {artifact}/")


def install_dependencies():
    """Install Python dependencies to package/ directory using Docker for Lambda compatibility"""
    print("\n📦 Installing dependencies using Docker (Lambda-compatible environment)...")
    package_dir = Path("package")
    package_dir.mkdir(exist_ok=True)
    
    # Use Amazon Linux 2023 Docker image (same as Lambda Python 3.11 runtime)
    # Override entrypoint to run pip directly
    docker_cmd = [
        "docker", "run", "--rm",
        "--entrypoint", "pip",
        "-v", f"{Path.cwd().absolute()}:/workspace",
        "-w", "/workspace",
        "public.ecr.aws/lambda/python:3.11",
        "install",
        "-r", "requirements.txt",
        "-t", "package/",
        "--upgrade"
    ]
    
    result = subprocess.run(docker_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"❌ Failed to install dependencies:\n{result.stderr}")
        print("\n⚠️  Make sure Docker is running!")
        sys.exit(1)
    
    print("   ✅ Dependencies installed (Lambda-compatible binaries)")


def create_deployment_package():
    """Create deployment.zip with application code and dependencies"""
    print("\n📦 Creating deployment package...")
    
    with zipfile.ZipFile("deployment.zip", "w", zipfile.ZIP_DEFLATED) as zipf:
        # Add dependencies from package/
        package_dir = Path("package")
        if package_dir.exists():
            for root, dirs, files in os.walk(package_dir):
                # Skip __pycache__ but KEEP .dist-info directories (needed for metadata)
                dirs[:] = [d for d in dirs if d != "__pycache__"]
                
                for file in files:
                    if file.endswith(".pyc"):
                        continue
                    
                    file_path = Path(root) / file
                    arcname = file_path.relative_to(package_dir)
                    zipf.write(file_path, arcname)
                    
        print(f"   Added dependencies from package/")
        
        # Add application code
        app_dirs = ["app", "admin"]
        for app_dir in app_dirs:
            dir_path = Path(app_dir)
            if dir_path.exists():
                for root, dirs, files in os.walk(dir_path):
                    # Skip __pycache__
                    dirs[:] = [d for d in dirs if d != "__pycache__"]
                    
                    for file in files:
                        if file.endswith(".pyc"):
                            continue
                        
                        file_path = Path(root) / file
                        arcname = file_path
                        zipf.write(file_path, arcname)
                
                print(f"   Added {app_dir}/ directory")
    
    # Get file size
    zip_size = Path("deployment.zip").stat().st_size
    zip_size_mb = zip_size / (1024 * 1024)
    
    print(f"\n✅ Deployment package created: deployment.zip ({zip_size_mb:.2f} MB)")
    
    if zip_size_mb > 50:
        print(f"⚠️  Warning: Package size exceeds 50 MB Lambda limit!")
        sys.exit(1)


def main():
    """Main build process"""
    print("=" * 60)
    print("Building Lambda Deployment Package (ZIP)")
    print("=" * 60)
    
    # Ensure we're in the project root
    if not Path("requirements.txt").exists():
        print("❌ Error: requirements.txt not found. Run this script from project root.")
        sys.exit(1)
    
    try:
        clean_build_artifacts()
        install_dependencies()
        create_deployment_package()
        
        print("\n" + "=" * 60)
        print("✅ Build complete! Ready to deploy deployment.zip")
        print("=" * 60)
        
    except KeyboardInterrupt:
        print("\n\n⚠️  Build cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Build failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
