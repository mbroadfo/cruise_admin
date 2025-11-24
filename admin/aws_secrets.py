import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from admin.parameter_store import inject_auth0_credentials


def inject_env_from_secrets(region_name: str = "us-west-2") -> None:
    """
    Loads Auth0 credentials from AWS Systems Manager Parameter Store 
    and injects them into environment variables.
    
    Args:
        region_name: AWS region name (default: us-west-2)
    
    The credentials are loaded from the Parameter Store parameter:
    /cruise-admin/prod/auth0-credentials
    """
    print("🔧 Loading credentials from Parameter Store...")
    inject_auth0_credentials(region_name)
