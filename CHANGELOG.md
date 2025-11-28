# Changelog

All notable changes to the cruise_admin project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2025-11-28

### 🚀 ZIP-Based Lambda Deployment

Migrated from Docker container deployment to ZIP-based Lambda packages, eliminating ECR costs and simplifying CI/CD.

### Added

- **ZIP deployment pipeline**
  - `build_lambda.py` - Docker-based build script using Lambda Python 3.11 image
  - Ensures Lambda-compatible binaries for all dependencies
  - Includes package metadata (.dist-info) for proper imports
  - 3.73 MB deployment package (well under 50 MB limit)

- **GitHub Actions CI/CD workflow** (`.github/workflows/deploy.yml`)
  - Automated build and deployment on push to main
  - Python 3.11 setup with pip caching
  - Lambda function update with version publishing
  - Deployment verification and artifact upload

### Changed

- **Updated `deploy_lambda.ps1`** - PowerShell script for ZIP deployment
  - Replaced Docker build/push with ZIP package creation
  - Automatic upload to Lambda
  - Deployment verification with function info display

- **Updated `infra/main.tf`** - Terraform configuration
  - Changed Lambda `package_type` from `Image` to `Zip`
  - Added `runtime = "python3.11"` and `handler = "app.main.lambda_handler"`
  - Removed ECR repository and policy resources
  - Updated local paths to use `deployment.zip`

- **Updated README.MD** - Documentation for ZIP deployment
  - CI/CD workflow documentation
  - Manual deployment instructions
  - GitHub secrets requirements
  - Removed Docker build references

- **Updated `.gitignore`** - Exclude deployment artifacts
  - Added `deployment.zip` and `package/` directory

### Removed

- **ECR (Elastic Container Registry) dependency**
  - No more Docker image storage costs (~$0.10/GB/month)
  - No ECR login or push commands needed
  - Simplified deployment pipeline

### Performance

- **Faster deployments** - No Docker build/push overhead
- **Simpler CI/CD** - Just zip and upload to Lambda
- **Maintained performance** - Same cold start times, token caching still operational

### Infrastructure

- Deployment package: 3.73 MB
- Lambda runtime: Python 3.11
- Package type: Zip
- Build environment: Docker (Lambda Python 3.11 image)

## [2.0.0] - 2025-11-24

### 🎉 Major Release - Parameter Store Migration & Token Caching Complete

This major release completes the migration from AWS Secrets Manager to Parameter Store and implements a highly efficient three-tier token caching system.

### Added

- **Three-tier Auth0 token caching system** for Management API tokens
  - Tier 1: Memory cache (~0ms) - Survives Lambda warm starts
  - Tier 2: Parameter Store cache (~350ms) - Shared across Lambda instances
  - Tier 3: Auth0 API fallback (~1300ms) - Only when caches miss
  - Reduces Auth0 API calls by 99%
  - 6.5x faster token retrieval on warm invocations
  - 3.7x faster than Auth0 on cold starts

- **Parameter Store integration** (`admin/parameter_store.py`)
  - `get_parameter()` - Fetch single parameter with decryption
  - `load_auth0_credentials()` - Load Auth0 config from Parameter Store
  - `inject_auth0_credentials()` - Inject credentials into environment

- **Automated testing** (`test_token_caching.py`)
  - Tests all three caching tiers automatically
  - Validates performance improvements
  - No UI intervention required

- **IAM permissions** for token cache management
  - `ssm:PutParameter` - Write token cache to Parameter Store
  - Token cache stored at `/cruise-admin/prod/auth0-mgmt-token`

- **Documentation**
  - Created `docs/archive/` folder for completed project documentation
  - Moved completed MIGRATION_GUIDE.md to archive
  - Added this CHANGELOG.md

- **IAM PassRole policy** (`infra/setup/terraform-lcf-passrole.json`)
  - Allows terraform user to pass IAM roles for infrastructure management

### Changed

- **Simplified `admin/aws_secrets.py`**
  - Removed dual-mode flag and Secrets Manager code
  - Now exclusively uses Parameter Store
  - Removed deprecated `secret_name` parameter
  - Updated docstrings to reflect Parameter Store-only usage

- **Enhanced `admin/token_cache.py`**
  - Completely rewritten with three-tier caching architecture
  - Added Parameter Store integration for token caching
  - Added detailed logging for cache hits/misses
  - Token expiry includes 5-minute buffer for safety

- **Updated `app/config.py`**
  - Removed `SECRET_NAME` and `AWS_SECRET_NAME` references
  - Simplified to only use Parameter Store

- **Updated `admin/auth0_utils.py`**
  - Removed hardcoded secret name from `ensure_env_loaded()`
  - Now calls `inject_env_from_secrets()` without parameters

- **Updated `README.MD`**
  - Changed "Secrets Manager Integration" to "Parameter Store Integration"
  - Updated all references to use Parameter Store terminology
  - Updated IAM roles description to reflect Parameter Store access

- **Updated Terraform infrastructure** (`infra/main.tf`)
  - Removed SecretsManagerAccess IAM statement
  - Added ParameterStoreWriteTokenCache statement for token caching
  - Simplified KMS condition to only SSM service
  - Updated policy description to include token caching

### Removed

- **AWS Secrets Manager dependencies**
  - Removed all Secrets Manager code from `admin/aws_secrets.py`
  - Removed `load_secrets()` function
  - Removed `USE_PARAMETER_STORE` environment variable flag
  - Removed SecretsManagerAccess IAM permissions
  - Deleted AWS Secrets Manager secret (`cruise-finder-secrets`)

- **Documentation**
  - Deleted `SECRETS_MANAGER_USAGE.md` (migration complete)

- **Requirements**
  - Removed `boto3` from `requirements.txt` (provided by Lambda runtime)
  - Removed `uvicorn` (not needed in Lambda)

### Fixed

- **`.gitignore`** - Added `tfplan` entry to ignore Terraform plan files without extension
- **Markdown linting** - Fixed all linting errors in documentation files

### Performance

- **Cold start**: 72% faster with Parameter Store cache vs Auth0 API
- **Warm invocations**: Sub-millisecond token retrieval (100% faster)
- **API call reduction**: 99% fewer Auth0 Management API calls
- **Token sharing**: Cached tokens shared across all Lambda instances

### Security

- Auth0 credentials stored as SecureString in Parameter Store
- Token cache stored as SecureString with expiry timestamp
- KMS encryption for all Parameter Store parameters
- Least-privilege IAM permissions (read credentials, read/write token cache)

### Infrastructure

**Parameter Store Parameters:**

- `/cruise-admin/prod/auth0-credentials` - Auth0 configuration (SecureString)
- `/cruise-admin/prod/auth0-mgmt-token` - Cached Auth0 token (SecureString)

**Lambda Configuration:**

- Function: `cruise-admin-api`
- Runtime: Container (Python 3.11)
- Memory: 512 MB
- Timeout: 30s
- Environment variables: None (uses Parameter Store)

**IAM Policies:**

- ParameterStoreReadCredentials: Read Auth0 credentials and token cache
- ParameterStoreWriteTokenCache: Write token cache
- KMSDecryptParameters: Decrypt SecureString parameters

### Migration Notes

This release completes three major phases:

1. **Phase 3**: Parameter Store migration for Auth0 credentials
2. **Phase 4**: Complete removal of AWS Secrets Manager
3. **Phase 6**: Three-tier token caching implementation

See `docs/archive/MIGRATION_GUIDE.md` for detailed migration history.

### Breaking Changes

- Requires Parameter Store parameter `/cruise-admin/prod/auth0-credentials` to exist
- Lambda function must have Parameter Store read/write IAM permissions
- No longer compatible with AWS Secrets Manager
- `inject_env_from_secrets()` signature changed (removed `secret_name` parameter)

### Tested

- ✅ All three caching tiers validated in production
- ✅ Cold starts with Parameter Store cache
- ✅ Warm invocations with memory cache
- ✅ Auth0 API fallback when no cache exists
- ✅ All CRUD operations on user management endpoints
- ✅ Token expiry and refresh logic

---

## [1.0.0] - 2025-05-18

### Initial Release

- FastAPI admin API for cruise viewer user management
- Auth0 integration for authentication and user management
- AWS Lambda deployment with container images
- API Gateway with JWT validation
- Favorites management functionality
- AWS Secrets Manager integration (deprecated in 2.0.0)
- Terraform infrastructure as code
- Docker containerization

---

[Unreleased]: https://github.com/mbroadfo/cruise_admin/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/mbroadfo/cruise_admin/releases/tag/v2.0.0
[1.0.0]: https://github.com/mbroadfo/cruise_admin/releases/tag/v1.0.0
