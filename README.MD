# Cruise Admin Backend

This is the admin API for managing users and favorites for the Cruise Viewer platform. It is implemented using FastAPI and deployed as an AWS Lambda container behind API Gateway. The backend is secured using Auth0 JWT validation and integrates with Auth0 Management API for user operations.

---

## Features

* **JWT-Protected REST API** via API Gateway and Lambda
* **Auth0 Integration** for user management and metadata
* **Favorites Management** for expeditions
* **Idle-aware Lambda**: Automatically tracks last user activity
* **Secrets Manager Integration** for secure config injection
* **Click-based CLI Tool** for local user management
* **Complete Terraform Infrastructure**: API Gateway, Lambda, IAM, Auth0 settings
* **CORS and Preflight Support** for SPA compatibility

---

## Project Structure

```
cruise-admin/
├── src/
│   ├── api.py               # FastAPI routes
│   ├── auth.py              # JWT verification, Auth0 role parsing
│   ├── config.py            # Env + AWS Secrets manager integration
│   ├── lambda_handler.py    # Mangum bridge and CloudWatch logging
│   ├── token_cache.py       # Cached Auth0 Management API token logic
│   ├── auth0_utils.py       # Create/find/update/delete Auth0 users
│   └── middleware.py        # Last activity timestamp tracking
│
├── cli/
│   └── auth0_cli.py         # Click CLI for managing users
│
├── tests/
│   └── test_update_favorites.py  # Sample test case
│
├── Dockerfile              # Lambda-compatible container
├── Makefile                # Build/deploy shortcuts
├── terraform/              # Full AWS + Auth0 setup
└── requirements.txt        # Python dependencies
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

## Deployment & CI/CD

This app is containerized using Docker and deployed to AWS Lambda as a container image. CI/CD steps:

1. GitHub Actions builds image and pushes to ECR
2. Terraform applies infrastructure (`terraform/` directory)
3. Lambda is updated with latest image tag

Environment configuration and Auth0 secrets are stored in **AWS Secrets Manager** and injected at runtime using the custom `inject_env_from_secrets` logic.

---

## Terraform Infrastructure

* **Lambda Function**: Container-based, idle-aware
* **API Gateway**: JWT-secured, CORS-enabled, with dynamic routes
* **IAM Roles**: Least-privilege setup with read access to Secrets Manager
* **CloudWatch**: Basic logging + last activity timestamp
* **Auth0 Integration**: Domain, client, audience, secret configured via secrets

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
make build

# Run CLI to create/delete/test users
python cli/auth0_cli.py list-users
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
