# Cruise Admin Backend

This is the admin API for managing users and favorites for the Cruise Viewer platform. It is implemented using FastAPI and deployed as an AWS Lambda container behind API Gateway. The backend is secured using Auth0 JWT validation and integrates with Auth0 Management API for user operations.

---

## Features

* **JWT-Protected REST API** via API Gateway and Lambda
* **Auth0 Integration** for user management and metadata
* **Favorites Management** for expeditions
* **Idle-aware Lambda**: Automatically tracks last user activity
* **Parameter Store Integration** for secure config injection
* **Click-based CLI Tool** for local user management
* **Complete Terraform Infrastructure**: API Gateway, Lambda, IAM, Auth0 settings
* **CORS and Preflight Support** for SPA compatibility

---

## Project Structure

``` text
cruise-admin/
├── app/
│   ├── main.py              # FastAPI routes and Mangum handler
│   ├── config.py            # Env + AWS Parameter Store integration
│   ├── models.py            # Pydantic models
│   └── shutdown.py          # Idle-aware shutdown tracking
│
├── admin/
│   ├── auth0_cli.py         # Click CLI for managing users
│   ├── auth0_utils.py       # Create/find/update/delete Auth0 users
│   ├── aws_secrets.py       # Parameter Store credential injection
│   ├── parameter_store.py   # Parameter Store utilities
│   └── token_cache.py       # Three-tier Auth0 token caching
│
├── tests/
│   └── test_*.py            # Test suite
│
├── infra/
│   └── main.tf              # Terraform infrastructure
│
├── Dockerfile               # Lambda-compatible container
├── deploy_lambda.ps1        # Manual deployment script
└── requirements.txt         # Python dependencies
```

---

## API Endpoints

### User Management (Admin Only)

* `GET /admin-api/users` - List users
* `POST /admin-api/users` - Create user
* `DELETE /admin-api/users/{id}` - Delete user

### Favorites

* `GET /user-api/favorites` - Read current user favorites
* `PUT /user-api/favorites` - Update favorites

---

## Deployment

This app is containerized using Docker and deployed to AWS Lambda as a container image.

**Manual Deployment Process**:

1. Run `deploy_lambda.ps1` to build and push Docker image to ECR
2. Update Lambda function with new image URI (or use Terraform)
3. Apply infrastructure changes with Terraform if needed (`infra/` directory)

Environment configuration and Auth0 credentials are stored in **AWS Systems Manager Parameter Store** (`/cruise-admin/prod/auth0-credentials`) and injected at runtime. Auth0 Management API tokens are cached using a three-tier system (memory → Parameter Store → Auth0 API) for optimal performance.

---

## Terraform Infrastructure

All infrastructure is defined in `infra/main.tf`:

* **Lambda Function**: Container-based, idle-aware, with Parameter Store access
* **API Gateway**: JWT-secured, CORS-enabled, with dynamic routes
* **IAM Roles**: Least-privilege setup with read/write access to Parameter Store
* **CloudWatch**: Basic logging + last activity timestamp
* **Auth0 Integration**: Credentials configured via Parameter Store

---

## Security Highlights

* All API routes protected by **JWTs issued by Auth0**
* Role-based access control (admin vs user) enforced by `require_admin`
* No secrets or tokens stored in source or frontend
* CLI operations protected via environment-based token fetch

---

## Running Locally

```bash
# Build container for local testing
docker build --platform linux/amd64 -t cruise-admin-api:local .

# Run CLI to manage users (requires AWS credentials and Parameter Store access)
python admin/auth0_cli.py list-users
```

---

## Future Enhancements

* Add unit test coverage for user create/delete
* Improve logging structure for CloudWatch
* Consider warm-up pings to reduce cold start
* Extend admin panel with audit logs and metrics

---

## License

MIT License. All trademarks and names belong to their respective owners.

---

## Authors

Maintained by the Cruise Viewer team. Contributions welcome!
