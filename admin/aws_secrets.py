import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from admin.parameter_store import inject_auth0_credentials


def inject_env_from_secrets(secret_name: str = None, region_name: str = "us-west-2") -> None:
    """
    Loads Auth0 credentials from Parameter Store and injects into environment variables.
    
    Note: secret_name parameter is deprecated and ignored (kept for backwards compatibility).
    Credentials are always loaded from Parameter Store at /cruise-admin/prod/auth0-credentials.
    """
    print("🔧 Loading credentials from Parameter Store...")
    inject_auth0_credentials(region_name)
