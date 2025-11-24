# AWS Secrets Manager Usage - cruise_admin

**Repository:** cruise_admin  
**Purpose:** FastAPI backend for managing users and favorites (deployed as AWS Lambda)  
**Date Generated:** November 23, 2025

---

## Overview

This document catalogs all uses of AWS Secrets Manager in the `cruise_admin` repository. Use this information when migrating to an alternative secrets management solution.

---

## 1. Python Implementation Files

### 1.1 `admin/aws_secrets.py`

**Purpose:** Core secrets management module  
**Functions:**

- `load_secrets(secret_name: str, region_name: str = "us-west-2") -> dict`
  - Fetches and parses secret JSON from AWS Secrets Manager
  - Uses boto3 `secretsmanager` client
  - Calls `get_secret_value` API
  - Returns parsed JSON dictionary
  
- `inject_env_from_secrets(secret_name: str, region_name: str = "us-west-2") -> None`
  - Loads secrets and injects them as environment variables
  - Only sets variables that don't already exist in `os.environ`
  - Allows CI/CD overrides

**Dependencies:**

- `boto3` - AWS SDK for Python
- `json` - JSON parsing
- `botocore.exceptions.ClientError` - Error handling

**API Calls:**

- `boto3.session.Session()`
- `session.client(service_name="secretsmanager", region_name=region_name)`
- `client.get_secret_value(SecretId=secret_name)`

---

### 1.2 `app/config.py`

**Location:** Lines 2, 9  
**Usage:**

```python
from admin.aws_secrets import inject_env_from_secrets

SECRET_NAME = os.getenv("AWS_SECRET_NAME", "cruise-finder-secrets")
REGION_NAME = os.getenv("AWS_REGION", "us-west-2")

# Inject secrets into environment
inject_env_from_secrets(SECRET_NAME, REGION_NAME)
```

**Secrets Retrieved:**

- `AUTH0_DOMAIN` - Auth0 tenant domain
- `AUTH0_CLIENT_ID` - Auth0 M2M client ID
- `AUTH0_CLIENT_SECRET` - Auth0 M2M client secret
- `AUTH0_WEB_CLIENT_ID` - Auth0 SPA client ID
- `AUTH0_CONNECTION` - Auth0 database connection name (defaults to "Username-Password-Authentication")
- `CLOUD_FRONT_URI` - CloudFront distribution URL
- `REDIRECT_URI` - Auth0 redirect URI for password resets

**Purpose:**

- Loads all Auth0 configuration at Lambda cold start
- Makes credentials available to entire application via environment variables

---

### 1.3 `admin/auth0_utils.py`

**Location:** Lines 6, 12  
**Usage:**

```python
from admin.aws_secrets import inject_env_from_secrets

def ensure_env_loaded() -> None:
    if not os.getenv("AUTH0_DOMAIN"):
        inject_env_from_secrets("cruise-finder-secrets")
```

**Purpose:**

- Lazy-loads secrets if not already in environment
- Used by all Auth0 user management functions:
  - `create_user()`
  - `send_password_reset_email()`
  - `find_user()`
  - `delete_user()`
  - `get_all_users()`
  - `update_user_favorites()`

**Secrets Used:**

- `AUTH0_DOMAIN` - Required for all Auth0 API calls
- `AUTH0_WEB_CLIENT_ID` - Required for password reset emails
- `AUTH0_CONNECTION` - Required for user creation and password resets
- `REDIRECT_URI` - Used in password reset flow

---

## 2. Infrastructure (Terraform)

### 2.1 `infra/main.tf`

#### IAM Policy - Lambda Secrets Access

**Resource:** `aws_iam_policy.lambda_secrets_access`  
**Location:** Lines 72-84  
**Policy Definition:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue"],
    "Resource": "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:cruise-finder-secrets*"
  }]
}
```

**Applied To:**

- `aws_iam_role.lambda_exec` (via `lambda_secrets_attach` attachment)

**Purpose:**

- Grants Lambda function permission to read the specific secret
- Properly scoped to exact secret ARN (includes wildcard suffix for versioning)
- More secure than wildcard resource

---

#### IAM Role - Lambda Execution

**Resource:** `aws_iam_role.lambda_exec`  
**Location:** Lines 56-66  
**Attached Policies:**

1. `AWSLambdaBasicExecutionRole` (CloudWatch Logs)
2. `lambda_secrets_access` (Secrets Manager)

**Trust Policy:**

```json
{
  "Principal": { "Service": "lambda.amazonaws.com" },
  "Action": "sts:AssumeRole"
}
```

---

## 3. Secret Name & Configuration

### Secret Details

- **Secret Name:** `cruise-finder-secrets`
- **AWS Region:** `us-west-2`
- **Format:** JSON key-value pairs
- **ARN Pattern:** `arn:aws:secretsmanager:us-west-2:491696534851:secret:cruise-finder-secrets*`

### Known Secret Keys

Based on code analysis, the secret contains:

1. `AUTH0_DOMAIN` - Auth0 tenant domain (e.g., "yourtenant.auth0.com")
2. `AUTH0_CLIENT_ID` - Auth0 Machine-to-Machine client ID
3. `AUTH0_CLIENT_SECRET` - Auth0 M2M client secret
4. `AUTH0_WEB_CLIENT_ID` - Auth0 SPA application client ID
5. `AUTH0_CONNECTION` - Auth0 database connection name
6. `CLOUD_FRONT_URI` - CloudFront distribution URL
7. `REDIRECT_URI` - Auth0 post-password-reset redirect URL

---

## 4. Dependencies

### Python Requirements (`requirements.txt`)

```text
boto3  # Required for Secrets Manager access
```

**Note:** boto3 must be installed in Lambda container for `aws_secrets.py` to function.

---

## 5. Execution Flow

### Lambda Cold Start Sequence

1. **Lambda Handler Init:** `app/lambda_handler.py` imports `app.main`
2. **Config Module Load:** `app/config.py` executes at import time
3. **Secret Retrieval:** `inject_env_from_secrets()` called immediately
4. **boto3 Call:** Fetches secret from AWS Secrets Manager via IAM role
5. **Environment Population:** All secret keys become environment variables
6. **App Initialization:** FastAPI app can now access Auth0 credentials

### Auth0 Operations Flow

```text
API Request → Lambda Handler → FastAPI Route → auth0_utils function
                                                    ↓
                                           ensure_env_loaded()
                                                    ↓
                                        (if needed) inject_env_from_secrets()
                                                    ↓
                                            Auth0 API Call
```

---

## 6. API Endpoints That Depend on Secrets

### Admin Endpoints (Require Secrets)

1. **GET `/admin-api/users`**
   - Uses: `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`
   - Function: `get_all_users()`

2. **POST `/admin-api/users`**
   - Uses: `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`, `AUTH0_CONNECTION`, `AUTH0_WEB_CLIENT_ID`, `REDIRECT_URI`
   - Functions: `create_user()`, `send_password_reset_email()`

3. **DELETE `/admin-api/users/{user_id}`**
   - Uses: `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`
   - Functions: `find_user()`, `delete_user()`

### User Endpoints (Require Secrets)

1. **PATCH `/admin-api/user/favorites`**
   - Uses: `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`
   - Function: `update_user_favorites()`

2. **GET `/admin-api/user`**
   - Uses: `AUTH0_DOMAIN` (for JWT validation context)
   - Function: Extracts user info from JWT

---

## 7. Auth0 Token Management

### Management API Token Acquisition

**Module:** `admin/token_cache.py` (not shown but referenced)  
**Function:** `get_auth0_mgmt_token()`  
**Dependencies:**

- `AUTH0_DOMAIN`
- `AUTH0_CLIENT_ID`
- `AUTH0_CLIENT_SECRET`

**Purpose:**

- Obtains M2M access token for Auth0 Management API
- Token cached to reduce Auth0 API calls
- Required for all user management operations

---

## 8. AWS Service Integration Points

### Services That Depend on Secrets Manager

1. **AWS Lambda Function**
   - Retrieves secrets via IAM role on cold start
   - Secrets cached in memory during warm starts
   - No persistent storage

2. **Auth0 Management API**
   - All credentials from Secrets Manager
   - Used for CRUD operations on users
   - Token caching reduces secret reads

3. **Auth0 Password Reset**
   - Email sending via Auth0 API
   - Requires `AUTH0_WEB_CLIENT_ID`, `REDIRECT_URI`, `AUTH0_CONNECTION`

---

## 9. Security Considerations

### Current Implementation Strengths

1. **Scoped IAM Resource:**
   - Policy correctly scopes to specific secret ARN
   - Includes wildcard for version suffixes
   - Follows least-privilege principle

2. **No Secret Logging:**
   - Secrets not printed in CloudWatch Logs
   - Errors logged without exposing values

3. **Environment Override:**
   - CI/CD can override secrets via environment variables
   - Useful for testing without modifying secrets

### Potential Issues

1. **Cold Start Latency:**
   - Secrets fetched on every cold start
   - Adds 50-200ms to initialization

2. **No Secret Rotation Support:**
   - Application must be redeployed to pick up new secrets
   - Warm Lambda containers cache old values

3. **Shared Secret Across Repos:**
   - `cruise-finder-secrets` used by both cruise_admin and cruise_finder
   - Broad scope increases risk if compromised

---

## 10. Migration Checklist

When replacing AWS Secrets Manager, update:

- [ ] `admin/aws_secrets.py` - Replace entire module
- [ ] `app/config.py` - Update secret loading mechanism
- [ ] `admin/auth0_utils.py` - Update `ensure_env_loaded()` function
- [ ] `infra/main.tf` - Remove `aws_iam_policy.lambda_secrets_access`
- [ ] `infra/main.tf` - Remove `aws_iam_role_policy_attachment.lambda_secrets_attach`
- [ ] `requirements.txt` - Evaluate if boto3 still needed (may be required for other AWS SDK usage)
- [ ] Update Lambda environment variables or new secret source
- [ ] Test cold start behavior with new secrets mechanism
- [ ] Verify Auth0 API calls work correctly
- [ ] Test all API endpoints:
  - [ ] GET /admin-api/users
  - [ ] POST /admin-api/users
  - [ ] DELETE /admin-api/users/{user_id}
  - [ ] PATCH /admin-api/user/favorites
  - [ ] GET /admin-api/user
- [ ] Update documentation and README
- [ ] Update CI/CD pipeline if needed

---

## 11. Alternative Solutions to Consider

### Option 1: Lambda Environment Variables

**Pros:**

- No cold start latency for secret retrieval
- Secrets encrypted at rest by AWS
- No additional IAM permissions needed

**Cons:**

- Secrets visible in Lambda console (to authorized users)
- Manual rotation requires redeployment
- Not suitable for frequently rotated secrets

**Implementation:**

- Add environment variables to Lambda function in Terraform
- Remove `inject_env_from_secrets()` calls
- Simplify `config.py` to just read from `os.getenv()`

---

### Option 2: AWS Systems Manager Parameter Store

**Pros:**

- Similar to Secrets Manager, simpler
- Lower cost ($0.05 per 10,000 API calls vs $0.40 for Secrets Manager)
- Supports versioning and parameter hierarchies

**Cons:**

- No automatic rotation
- 4KB value size limit (Secrets Manager: 64KB)
- Less feature-rich

**Implementation:**

- Replace `secretsmanager` client with `ssm` client
- Use `get_parameter(Name='/cruise-admin/auth0', WithDecryption=True)`
- Update IAM policy to `ssm:GetParameter`

---

### Option 3: AWS AppConfig

**Pros:**

- Built-in deployment safety features
- Gradual rollout of configuration changes
- Supports validation before deployment

**Cons:**

- More complex setup
- Primarily designed for feature flags/config, not secrets
- Higher learning curve

**Implementation:**

- Create AppConfig application and environment
- Store secrets as configuration profile
- Use AppConfig Lambda extension for caching

---

### Option 4: HashiCorp Vault

**Pros:**

- Enterprise-grade secrets management
- Dynamic secrets generation
- Excellent audit logging
- Multi-cloud support

**Cons:**

- Requires separate Vault infrastructure
- Additional cost and maintenance
- More complexity than AWS-native solutions

**Implementation:**

- Deploy Vault cluster or use HCP Vault
- Install Vault Python SDK
- Replace `aws_secrets.py` with Vault client
- Configure Vault AWS auth method for Lambda

---

### Option 5: Doppler (SaaS)

**Pros:**

- Simple developer experience
- Automatic syncing to AWS/other platforms
- Built-in secret rotation reminders
- Team collaboration features

**Cons:**

- External dependency (SaaS)
- Additional monthly cost
- Requires internet access (Lambda already has this)

**Implementation:**

- Create Doppler project
- Install Doppler CLI or SDK
- Use Doppler Lambda extension or SDK
- Sync secrets at deployment time

---

## 12. Recommended Migration Path

### Phase 1: Preparation

1. Create new secret storage (e.g., Parameter Store or Environment Variables)
2. Copy current secrets from Secrets Manager to new location
3. Update one non-production Lambda function to test

### Phase 2: Code Updates

1. Create feature flag to switch between Secrets Manager and new solution
2. Update `admin/aws_secrets.py` to support both methods
3. Test thoroughly in dev/staging environment

### Phase 3: Deployment

1. Deploy updated Lambda with dual-read capability
2. Monitor CloudWatch logs for any Auth0 failures
3. Verify all API endpoints function correctly

### Phase 4: Cleanup

1. Remove Secrets Manager code path once new solution validated
2. Remove IAM policies for Secrets Manager
3. Delete or deprecate old secret in AWS Secrets Manager
4. Update documentation

---

## 13. Testing Recommendations

Before removing Secrets Manager:

1. **Unit Tests:**
   - [ ] Mock secrets loading in tests
   - [ ] Test `config.py` with environment variables
   - [ ] Test `auth0_utils.py` functions

2. **Integration Tests:**
   - [ ] Test Lambda cold start with new secret source
   - [ ] Verify Auth0 token acquisition
   - [ ] Test user creation flow
   - [ ] Test user deletion flow
   - [ ] Test favorites update

3. **Load Tests:**
   - [ ] Measure cold start latency before/after
   - [ ] Test under concurrent Lambda invocations
   - [ ] Verify secret caching works as expected

4. **Security Tests:**
   - [ ] Confirm secrets not logged
   - [ ] Verify IAM permissions updated correctly
   - [ ] Test with invalid/expired secrets

---

## Additional Notes

- The `cruise-finder-secrets` secret is **shared** with `cruise_finder` repository
- Both repositories access the same secret in the same AWS region
- **Coordinate migration** with `cruise_finder` to avoid breaking dependencies
- Consider **splitting the secret** into two separate secrets after migration:
  - `cruise-finder-secrets` → Only AWS credentials, CloudFront config
  - `cruise-admin-secrets` → Only Auth0 credentials
- Current shared secret creates unnecessary coupling between services
- Separate secrets would allow independent rotation and access control

---

## 14. Monitoring & Rollback Plan

### Monitoring Post-Migration

- **CloudWatch Metrics:**
  - Lambda duration (check for increased latency)
  - Lambda errors (check for credential failures)
  - API Gateway 5xx errors

- **CloudWatch Logs:**
  - Search for "❌ Error retrieving secret"
  - Monitor Auth0 API response codes
  - Check for boto3 client errors

### Rollback Plan

1. Keep old `admin/aws_secrets.py` in version control
2. Tag the last working commit before migration
3. Prepare Terraform rollback (keep IAM policy in comments)
4. Document rollback command: `git revert <commit>; terraform apply`
5. Keep Secrets Manager secret active for 30 days post-migration

---

## Contact & Questions

For questions about this migration, contact the repository maintainers or reference:

- AWS Secrets Manager documentation: <https://docs.aws.amazon.com/secretsmanager/>
- Terraform AWS Provider docs: <https://registry.terraform.io/providers/hashicorp/aws/>
- boto3 Secrets Manager reference: <https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/secretsmanager.html>
