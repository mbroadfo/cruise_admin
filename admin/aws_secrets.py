import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import boto3
import json
from botocore.exceptions import ClientError

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
    """Sets secret values as environment variables."""
    secrets = load_secrets(secret_name, region_name)
    for key, value in secrets.items():
        if key not in os.environ:  # Don’t override pre-set vars (e.g., CI/CD)
            os.environ[key] = value
