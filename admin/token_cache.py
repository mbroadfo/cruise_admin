import os
import time
import requests
from typing import Optional

_auth0_mgmt_token: Optional[str] = None
_auth0_mgmt_token_expiry: float = 0.0  # Must match time.time()
TOKEN_CACHE_SECONDS = 24 * 60 * 60  # 24 hours

def get_env_or_raise(name: str) -> str:
    val = os.getenv(name)
    if not val:
        raise RuntimeError(f"{name} is not set in the environment")
    return val

def get_auth0_mgmt_token() -> Optional[str]:
    global _auth0_mgmt_token, _auth0_mgmt_token_expiry

    now = time.time()
    if _auth0_mgmt_token and now < _auth0_mgmt_token_expiry:
        return _auth0_mgmt_token

    AUTH0_DOMAIN = get_env_or_raise("AUTH0_DOMAIN")
    AUTH0_CLIENT_ID = get_env_or_raise("AUTH0_CLIENT_ID")
    AUTH0_CLIENT_SECRET = get_env_or_raise("AUTH0_CLIENT_SECRET")
    AUTH0_AUDIENCE = os.getenv("AUTH0_AUDIENCE", f"https://{AUTH0_DOMAIN}/api/v2/")

    url = f"https://{AUTH0_DOMAIN}/oauth/token"
    payload = {
        "grant_type": "client_credentials",
        "client_id": AUTH0_CLIENT_ID,
        "client_secret": AUTH0_CLIENT_SECRET,
        "audience": AUTH0_AUDIENCE,
    }
    headers = {"content-type": "application/json"}

    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()
    data = response.json()

    _auth0_mgmt_token = data["access_token"]
    _auth0_mgmt_token_expiry = now + TOKEN_CACHE_SECONDS - 60
    return _auth0_mgmt_token
