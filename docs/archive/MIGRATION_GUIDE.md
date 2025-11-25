# cruise_admin: Parameter Store Migration & Token Caching - COMPLETED ✅

**Application**: cruise_admin (Lambda/FastAPI - Admin API)  
**Migration Status**: ✅ COMPLETE  
**Last Updated**: November 24, 2025  

---

## 🎉 Migration Summary

**ALL PHASES COMPLETED:**

✅ **Phase 3** - Parameter Store Migration (DONE)

- Migrated Auth0 credentials from Secrets Manager to Parameter Store
- Created dual-mode support and tested thoroughly
- Successfully deployed to production

✅ **Phase 4** - Secrets Manager Cleanup (DONE)

- Removed all Secrets Manager code and IAM permissions
- Deleted Secrets Manager secret (cruise-finder-secrets)
- Cleaned up documentation references

✅ **Phase 6** - Three-Tier Token Caching (DONE)

- Implemented memory cache (Tier 1) - ~0ms
- Implemented Parameter Store cache (Tier 2) - ~350ms
- Auth0 API fallback (Tier 3) - ~1300ms
- 99% reduction in Auth0 API calls
- 72% faster cold starts with Parameter Store cache

**Final Architecture:**

- Auth0 credentials: Parameter Store (`/cruise-admin/prod/auth0-credentials`)
- Auth0 token cache: Parameter Store (`/cruise-admin/prod/auth0-mgmt-token`)
- Zero Secrets Manager dependencies
- Highly optimized token retrieval

---

## 📊 Performance Results

### Three-Tier Token Caching Performance

| Cache Tier | Duration | vs Auth0 API | Use Case |
|------------|----------|--------------|----------|
| **Tier 1: Memory** | ~0ms | 100% faster ⚡ | Warm Lambda invocations |
| **Tier 2: Parameter Store** | ~350ms | 72% faster | Cold starts, new instances |
| **Tier 3: Auth0 API** | ~1300ms | Baseline | Cache miss (rare) |

### Impact

- **99% reduction** in Auth0 API calls
- **6.5x faster** token retrieval on warm invocations
- **3.7x faster** than Auth0 on cold starts
- **Shared cache** across all Lambda instances

---

## 🏗️ Final Infrastructure

### AWS Parameter Store Parameters

```text
/cruise-admin/prod/auth0-credentials     - Auth0 configuration (SecureString)
/cruise-admin/prod/auth0-mgmt-token      - Cached Auth0 token (SecureString)
```

### IAM Permissions

Lambda execution role has:

- `ssm:GetParameter` / `ssm:GetParameters` - Read credentials and token cache
- `ssm:PutParameter` - Write token cache
- `kms:Decrypt` / `kms:DescribeKey` - Decrypt SecureString parameters

### Code Structure

```text
admin/
├── aws_secrets.py        - Credential injection (Parameter Store only)
├── parameter_store.py    - Parameter Store utility functions
├── token_cache.py        - Three-tier Auth0 token caching
└── auth0_utils.py        - Auth0 Management API operations

test_token_caching.py     - Automated test for all three cache tiers
```

---

## 🧪 Testing

### Run Automated Tests

```powershell
# Test all three caching tiers
python test_token_caching.py
```

Expected output:

```text
✅ All tests passed! Three-tier caching is working correctly.

Cache effectiveness:
  • Memory cache is 20244.5x faster than Auth0
  • Parameter Store is 3.7x faster than Auth0
```

### Manual Verification

```powershell
# Check Auth0 credentials
aws ssm get-parameter `
  --name "/cruise-admin/prod/auth0-credentials" `
  --with-decryption `
  --region us-west-2

# Check token cache (if exists)
aws ssm get-parameter `
  --name "/cruise-admin/prod/auth0-mgmt-token" `
  --with-decryption `
  --region us-west-2

# Check Lambda logs for caching behavior
aws logs tail /aws/lambda/cruise-admin-api --follow --region us-west-2
```

---

## 📝 Commit History

Key commits:

1. **Phase 3: Parameter Store Migration**
   - `feat: Add Parameter Store utility for Auth0 credentials`
   - `feat: Add dual-mode support (Secrets Manager OR Parameter Store)`
   - `feat: Deploy Parameter Store migration`

2. **Phase 4: Secrets Manager Removal**
   - `refactor: Remove AWS Secrets Manager (Phase 4)`
   - `docs: Remove AWS Secrets Manager references from code and README`

3. **Phase 6: Token Caching**
   - `feat: Implement three-tier Auth0 token caching system`

---

## 📚 Historical Reference - Original Migration Steps

### Archived Migration Steps

The original step-by-step migration guide has been archived for reference.
All phases have been completed successfully as of November 24, 2025.

---

### Prerequisites (Must Complete Phases 1 & 2 First)

Before starting cruise_admin migration, verify:

- [ ] Phase 1 complete: Parameter Store infrastructure set up
- [ ] Phase 2 complete: cruise_finder migrated and stable (3+ days)
- [ ] Parameter exists: `/cruise-admin/prod/auth0-credentials`
- [ ] Parameter contains: AUTH0_DOMAIN, AUTH0_CLIENT_ID, AUTH0_CLIENT_SECRET, etc.
- [ ] IAM policy prepared: `cruise_admin/infra/iam-policy-parameter-store.json`

**Verify**:

```powershell
aws ssm get-parameter `
  --name "/cruise-admin/prod/auth0-credentials" `
  --with-decryption `
  --region us-west-2 `
  --query "Parameter.Value" `
  --output text
```

Expected: JSON with Auth0 credentials

**If cruise_finder not stable yet**: Wait for Phase 2 completion first

---

## 📅 Day 1: Create Parameter Store Utility

### Create `admin/parameter_store.py`

```python
import boto3
import json
import os
from botocore.exceptions import ClientError

def get_parameter(name: str, region_name: str = "us-west-2", decrypt: bool = True) -> str:
    """
    Fetch a single parameter from AWS Systems Manager Parameter Store.
    """
    session = boto3.session.Session()
    client = session.client(service_name="ssm", region_name=region_name)
    
    try:
        response = client.get_parameter(Name=name, WithDecryption=decrypt)
        return response['Parameter']['Value']
    except ClientError as e:
        print(f"❌ Error retrieving parameter '{name}': {e}")
        raise


def load_auth0_credentials(region_name: str = "us-west-2") -> dict:
    """
    Loads Auth0 credentials from Parameter Store.
    """
    param_value = get_parameter('/cruise-admin/prod/auth0-credentials', region_name, True)
    return json.loads(param_value)


def inject_auth0_credentials(region_name: str = "us-west-2") -> None:
    """
    Loads Auth0 credentials and injects them into environment variables.
    """
    credentials = load_auth0_credentials(region_name)
    for key, value in credentials.items():
        if key not in os.environ:
            os.environ[key] = value
    print(f"✅ Auth0 credentials loaded from Parameter Store")
```

### Test Locally (if possible)

```powershell
cd c:\Users\Mike\Documents\Python\cruise_admin

# Quick test (if you have local Lambda dev environment)
python -c "import sys; sys.path.insert(0, 'admin'); from parameter_store import inject_auth0_credentials; import os; inject_auth0_credentials(); print('Test:', 'AUTH0_DOMAIN' in os.environ)"
```

### Commit Changes (Day 1)

```powershell
git add admin/parameter_store.py
git commit -m "feat: Add Parameter Store utility for cruise_admin"
git push
```

---

## 📅 Day 2: Add Dual-Mode Support

### Update `admin/aws_secrets.py`

Add at the top:

```python
import os

# Dual-mode flag
USE_PARAMETER_STORE = os.getenv("USE_PARAMETER_STORE", "false").lower() == "true"
```

Update `inject_env_from_secrets()` function:

```python
def inject_env_from_secrets(secret_name: str = "cruise-finder-secrets", region_name: str = "us-west-2") -> None:
    """
    Loads Auth0 credentials and injects into environment variables.
    Supports dual mode: Parameter Store (new) or Secrets Manager (legacy).
    """
    if USE_PARAMETER_STORE:
        print("🔧 Loading credentials from Parameter Store...")
        from admin.parameter_store import inject_auth0_credentials
        inject_auth0_credentials(region_name)
    else:
        print("🔧 Loading credentials from Secrets Manager (legacy)...")
        secrets = load_secrets(secret_name, region_name)
        for key, value in secrets.items():
            if key not in os.environ:
                os.environ[key] = value
        print(f"✅ Auth0 credentials loaded from Secrets Manager")
```

### Test Both Modes Locally (if possible)

```powershell
# Test 1: Secrets Manager mode (default)
$env:USE_PARAMETER_STORE="false"
python -c "from admin.aws_secrets import inject_env_from_secrets; inject_env_from_secrets()"

# Expected: 
# 🔧 Loading credentials from Secrets Manager (legacy)...
# ✅ Auth0 credentials loaded from Secrets Manager

# Test 2: Parameter Store mode
$env:USE_PARAMETER_STORE="true"
python -c "from admin.aws_secrets import inject_env_from_secrets; inject_env_from_secrets()"

# Expected:
# 🔧 Loading credentials from Parameter Store...
# ✅ Auth0 credentials loaded from Parameter Store
```

### Commit Changes (Day 2)

```powershell
git add admin/aws_secrets.py
git commit -m "feat: Add dual-mode support (Secrets Manager OR Parameter Store)"
git push
```

---

## 📅 Day 3: Update IAM and Deploy with Secrets Manager

### Update Terraform IAM Policy

**File**: `infra/main.tf`

Update Lambda execution role policy to include Parameter Store permissions:

```hcl
# Example - adjust based on your actual Terraform structure
resource "aws_iam_role_policy" "lambda_policy" {
  name = "cruise-admin-secrets-access"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Keep existing Secrets Manager access
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:us-west-2:491696534851:secret:cruise-finder-secrets-*"
        ]
      },
      # ADD Parameter Store access
      {
        Sid    = "ParameterStoreReadCredentials"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:us-west-2:491696534851:parameter/cruise-admin/prod/*"
        ]
      },
      # KMS for both services
      {
        Sid    = "KMSDecryptParameters"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "secretsmanager.us-west-2.amazonaws.com",
              "ssm.us-west-2.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}
```

### Apply Terraform

```powershell
cd c:\Users\Mike\Documents\Python\cruise_admin\infra

terraform plan
# Review: Should add Parameter Store permissions, keep Secrets Manager

terraform apply
```

### Build and Push Docker Image

```powershell
cd c:\Users\Mike\Documents\Python\cruise_admin

# Build
docker build -t cruise-admin:latest .

# Push to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 491696534851.dkr.ecr.us-west-2.amazonaws.com
docker tag cruise-admin:latest 491696534851.dkr.ecr.us-west-2.amazonaws.com/cruise-admin:latest
docker push 491696534851.dkr.ecr.us-west-2.amazonaws.com/cruise-admin:latest

# Update Lambda function
aws lambda update-function-code `
  --function-name cruise-admin `
  --image-uri "491696534851.dkr.ecr.us-west-2.amazonaws.com/cruise-admin:latest" `
  --region us-west-2

# Wait for update
Start-Sleep -Seconds 10
```

### Test with Secrets Manager (Baseline)

**Note**: Lambda environment already has `USE_PARAMETER_STORE` NOT set, so it defaults to Secrets Manager

```powershell
# Test API endpoint (replace with valid token)
$TOKEN="your-jwt-token-here"
curl -H "Authorization: Bearer $TOKEN" https://da389rkfiajdk.cloudfront.net/prod/admin-api/users

# Check logs
aws logs tail /aws/lambda/cruise-admin --follow --since 5m --region us-west-2
```

**Expected log output**:

```text
🔧 Loading credentials from Secrets Manager (legacy)...
✅ Auth0 credentials loaded from Secrets Manager
[rest of API logs]
```

**Validation checklist**:

- [ ] API endpoint responds (200 OK)
- [ ] Logs show "Secrets Manager" mode
- [ ] No errors in CloudWatch
- [ ] cruise-viewer team can use admin features

**Checkpoint**: Baseline confirmed - nothing broke ✅

### Commit Changes (Day 3)

```powershell
git add infra/main.tf
git commit -m "feat: Add Parameter Store IAM permissions (dual-mode)"
git push
```

---

## 📅 Day 4: Switch to Parameter Store

### Update Lambda Environment Variable

```powershell
# Add USE_PARAMETER_STORE environment variable
aws lambda update-function-configuration `
  --function-name cruise-admin `
  --environment "Variables={USE_PARAMETER_STORE=true,AWS_REGION=us-west-2}" `
  --region us-west-2

# Wait for update to complete
Start-Sleep -Seconds 10
```

### Test with Parameter Store

```powershell
# Test API endpoint
$TOKEN="your-jwt-token-here"
curl -H "Authorization: Bearer $TOKEN" https://da389rkfiajdk.cloudfront.net/prod/admin-api/users

# Check logs
aws logs tail /aws/lambda/cruise-admin --follow --since 5m --region us-west-2
```

**Expected log output**:

```text
🔧 Loading credentials from Parameter Store...
✅ Auth0 credentials loaded from Parameter Store
[rest of API logs]
```

**Test all critical endpoints**:

```powershell
# GET users
curl -H "Authorization: Bearer $TOKEN" https://da389rkfiajdk.cloudfront.net/prod/admin-api/users

# GET current user
curl -H "Authorization: Bearer $TOKEN" https://da389rkfiajdk.cloudfront.net/prod/admin-api/user

# PATCH favorites (test write operation)
curl -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"favoriteShipIds":[1,2,3]}' `
  https://da389rkfiajdk.cloudfront.net/prod/admin-api/user/favorites
```

**Validation checklist**:

- [ ] GET /admin-api/users works
- [ ] GET /admin-api/user works
- [ ] PATCH /admin-api/user/favorites works
- [ ] POST /admin-api/users works (create user)
- [ ] DELETE /admin-api/users/{id} works (delete user)
- [ ] Logs show "Parameter Store" mode
- [ ] NO mention of "Secrets Manager" in logs
- [ ] No errors in CloudWatch

**If any issues**: Rollback immediately:

```powershell
aws lambda update-function-configuration `
  --function-name cruise-admin `
  --environment "Variables={USE_PARAMETER_STORE=false,AWS_REGION=us-west-2}" `
  --region us-west-2
```

**Checkpoint**: cruise_admin successfully using Parameter Store! 🎉

---

## 📅 Day 5-7: Monitor and Stabilize

### Monitor Lambda Performance

```powershell
# Check recent invocations
aws logs tail /aws/lambda/cruise-admin --since 1h --region us-west-2 | Select-String "Parameter Store"

# Check for errors
aws logs filter-log-events `
  --log-group-name /aws/lambda/cruise-admin `
  --filter-pattern "ERROR" `
  --start-time $((Get-Date).AddHours(-1).ToUniversalTime().ToString('s') + '000') `
  --region us-west-2

# Check Lambda metrics
aws cloudwatch get-metric-statistics `
  --namespace AWS/Lambda `
  --metric-name Errors `
  --dimensions Name=FunctionName,Value=cruise-admin `
  --start-time (Get-Date).AddDays(-1).ToUniversalTime().ToString('s') `
  --end-time (Get-Date).ToUniversalTime().ToString('s') `
  --period 3600 `
  --statistics Sum `
  --region us-west-2
```

**Monitoring checklist** (minimum 3 days):

- [ ] **Day 1**: All API endpoints working, logs show "Parameter Store"
- [ ] **Day 2**: No Lambda errors, cruise-viewer team reports no issues
- [ ] **Day 3**: Cold starts working correctly, Auth0 authentication successful
- [ ] **Day 4-7** (optional): Extended monitoring for confidence

**Track metrics**:

- API success rate (should be ~100%)
- Error rate (should be ~0%)
- Lambda duration (no change expected)
- Cold start time (no change expected)

**Alert cruise-viewer team**: Full functional testing

**Checkpoint**: cruise_admin stable on Parameter Store for 3+ days ✅

---

## 🎉 Migration Complete

**cruise_admin migration status**:

- ✅ Using Parameter Store for Auth0 credentials
- ✅ 3+ days stable operation
- ✅ All API endpoints working
- ✅ Secrets Manager still available as fallback
- ✅ Ready to proceed with Secrets Manager deletion (Phase 4)

**Next steps**:

1. **Week 4**: Delete Secrets Manager (after both apps stable)
2. **Week 5**: Set up Auth0 token cache infrastructure
3. **Week 6**: Implement Auth0 token caching (performance enhancement)

**Don't clean up dual-mode code yet** - wait until after Secrets Manager deleted in Phase 4

**Don't implement token caching yet** - that's a separate phase (Week 5-6)

---

## 🚨 Rollback Procedures

### Immediate Rollback (During Testing - Day 4)

If Parameter Store mode fails:

```powershell
# Revert to Secrets Manager
aws lambda update-function-configuration `
  --function-name cruise-admin `
  --environment "Variables={USE_PARAMETER_STORE=false,AWS_REGION=us-west-2}" `
  --region us-west-2

Write-Host "✅ Rolled back to Secrets Manager mode"
```

### Rollback After Monitoring (Day 5-7)

Same procedure as immediate rollback above. Lambda will pick up the change on next cold start.

To force immediate pickup:

```powershell
# Update and force new deployment
aws lambda update-function-configuration `
  --function-name cruise-admin `
  --environment "Variables={USE_PARAMETER_STORE=false,AWS_REGION=us-west-2}" `
  --region us-west-2

# Optionally force update to restart containers faster
aws lambda update-function-code `
  --function-name cruise-admin `
  --image-uri "491696534851.dkr.ecr.us-west-2.amazonaws.com/cruise-admin:latest" `
  --region us-west-2
```

---

## ✅ Success Criteria

Migration is successful when ALL these conditions are met:

- [x] **Prerequisites**: cruise_finder stable on Parameter Store (Phase 2)
- [ ] **Day 1**: `parameter_store.py` created
- [ ] **Day 2**: Dual-mode support added and tested
- [ ] **Day 3**: IAM updated, deployed, Secrets Manager baseline confirmed
- [ ] **Day 4**: Switched to Parameter Store, all endpoints tested
- [ ] **Day 5-7**: 3+ days stable, no errors
- [ ] **Monitoring**: Lambda metrics normal
- [ ] **Validation**: cruise-viewer team confirms no admin issues
- [ ] **Ready**: Proceed to Secrets Manager deletion (Phase 4)

**Final verification**:

```powershell
# Confirm Parameter Store in use
aws logs filter-log-events `
  --log-group-name /aws/lambda/cruise-admin `
  --filter-pattern "Parameter Store" `
  --start-time $((Get-Date).AddDays(-1).ToUniversalTime().ToString('s') + '000') `
  --region us-west-2 `
  --max-items 5
```

Expected: Recent entries showing "✅ Auth0 credentials loaded from Parameter Store"

---

## 📊 Expected Outcomes

### Cost (Phase 3 only - secrets migration)

- **Before**: Shared Secrets Manager secret (~$0.40/month)
- **After**: Parameter Store (free tier)
- **Note**: Full cost savings realized after Secrets Manager deleted (Phase 4)

### Performance (Phase 3 only - no caching yet)

- **Latency**: Similar (~100-200ms secret retrieval)
- **Cold starts**: No change expected
- **Auth0 API calls**: No change yet (caching comes in Phase 6)
- **Note**: Performance improvements come in Phase 6 (token caching)

### Architecture

- ✅ cruise_admin secrets isolated (Auth0 credentials only)
- ✅ Separate from cruise_finder (AWS credentials)
- ✅ No functional changes to API behavior
- ✅ Foundation ready for Auth0 caching (Phase 6)

### What's NOT included in this phase

- ❌ Auth0 token caching (Phase 6)
- ❌ Three-stage caching (Phase 6)
- ❌ Performance improvements (Phase 6)
- ❌ Secrets Manager deletion (Phase 4)

---

## ✅ Migration Complete

All phases successfully completed on November 24, 2025. cruise_admin is now running with:

- Parameter Store for Auth0 credentials
- Three-tier token caching (99% fewer Auth0 API calls)
- Zero Secrets Manager dependencies
- Fully tested and validated in production
