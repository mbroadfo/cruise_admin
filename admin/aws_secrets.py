import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import boto3
import json
from botocore.exceptions import ClientError

# Dual-mode flag
USE_PARAMETER_STORE = os.getenv("USE_PARAMETER_STORE", "false").lower() == "true"

def load_secrets(secret_name: str, region_name: str = "us-west-2") -> dict:
    """Fetches and parses secret JSON from AWS Secrets Manager."""
    session = boto3.session.Session()
    client = session.client(service_name="secretsmanager", region_name=region_name)

    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret_str = response.get("SecretString")
        if not secret_str:
            raise ValueError(f"Secret {secret_name} has no SecretString")
        return json.loads(secret_str)
    except ClientError as e:
        print(f"❌ Error retrieving secret '{secret_name}': {e}")
        raise


def inject_env_from_secrets(secret_name: str, region_name: str = "us-west-2") -> None:
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
            if key not in os.environ:  # Don't override pre-set vars (e.g., CI/CD)
                os.environ[key] = value
        print(f"✅ Auth0 credentials loaded from Secrets Manager")
