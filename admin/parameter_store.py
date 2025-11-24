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
