import time
import requests
import os
from typing import Optional

_auth0_mgmt_token: Optional[str] = None
_auth0_mgmt_token_expiry: float = 0.0  # Must match time.time()

AUTH0_DOMAIN = os.environ["AUTH0_DOMAIN"]
AUTH0_CLIENT_ID = os.environ["AUTH0_CLIENT_ID"]
AUTH0_CLIENT_SECRET = os.environ["AUTH0_CLIENT_SECRET"]
AUTH0_AUDIENCE = os.environ.get("AUTH0_AUDIENCE", f"https://{AUTH0_DOMAIN}/api/v2/")

TOKEN_CACHE_SECONDS = 24 * 60 * 60  # 24 hours

def get_auth0_mgmt_token() -> str:
    global _auth0_mgmt_token, _auth0_mgmt_token_expiry

    now = time.time()
    if _auth0_mgmt_token and now < _auth0_mgmt_token_expiry:
        return _auth0_mgmt_token

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

    token = data["access_token"]
    _auth0_mgmt_token = token
    _auth0_mgmt_token_expiry = now + TOKEN_CACHE_SECONDS - 60

    return token