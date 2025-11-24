import os
import requests
import secrets
import string
from typing import List, Optional
from admin.aws_secrets import inject_env_from_secrets
from admin.token_cache import get_auth0_mgmt_token as get_m2m_token

# Only call secrets injection ONCE, at runtime
def ensure_env_loaded() -> None:
    if not os.getenv("AUTH0_DOMAIN"):
        inject_env_from_secrets()

def get_env_or_raise(name: str) -> str:
    val = os.getenv(name)
    if not val:
        raise RuntimeError(f"{name} is not set in the environment")
    return val

def generate_temp_password(length: int = 16) -> str:
    chars = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
    return ''.join(secrets.choice(chars) for _ in range(length))

def create_user(email: str, given_name: str, family_name: str, token: str) -> dict:
    ensure_env_loaded()
    AUTH0_DOMAIN = get_env_or_raise("AUTH0_DOMAIN")
    AUTH0_CONNECTION = os.getenv("AUTH0_CONNECTION", "Username-Password-Authentication")
    url = f"https://{AUTH0_DOMAIN}/api/v2/users"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    payload = {
        "email": email,
        "given_name": given_name,
        "family_name": family_name,
        "connection": AUTH0_CONNECTION,
        "email_verified": True,
        "password": generate_temp_password()
    }
    resp = requests.post(url, json=payload, headers=headers)
    resp.raise_for_status()
    return resp.json()

def send_password_reset_email(email: str, token: Optional[str] = None) -> None:
    ensure_env_loaded()
    AUTH0_DOMAIN = get_env_or_raise("AUTH0_DOMAIN")
    AUTH0_WEB_CLIENT_ID = get_env_or_raise("AUTH0_WEB_CLIENT_ID")
    AUTH0_CONNECTION = os.getenv("AUTH0_CONNECTION", "Username-Password-Authentication")
    REDIRECT_URI = os.getenv("REDIRECT_URI")

    url = f"https://{AUTH0_DOMAIN}/dbconnections/change_password"
    payload = {
        "client_id": AUTH0_WEB_CLIENT_ID,
        "email": email,
        "connection": AUTH0_CONNECTION,
        "redirect_uri": REDIRECT_URI
    }
    headers = {
        "Content-Type": "application/json"
    }

    resp = requests.post(url, json=payload, headers=headers)
    resp.raise_for_status()

def find_user(email: str) -> Optional[dict]:
    ensure_env_loaded()
    token = get_m2m_token()
    AUTH0_DOMAIN = get_env_or_raise("AUTH0_DOMAIN")
    url = f"https://{AUTH0_DOMAIN}/api/v2/users?q={email}"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers)
    resp.raise_for_status()
    users = resp.json()
    return users[0] if users else None

def delete_user(user_id: Optional[str]) -> None:
    ensure_env_loaded()
    token = get_m2m_token()
    AUTH0_DOMAIN = get_env_or_raise("AUTH0_DOMAIN")
    url = f"https://{AUTH0_DOMAIN}/api/v2/users/{user_id}"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.delete(url, headers=headers)
    resp.raise_for_status()

def get_all_users(token: str) -> List[dict]:
    ensure_env_loaded()
    AUTH0_DOMAIN = get_env_or_raise("AUTH0_DOMAIN")
    url = f"https://{AUTH0_DOMAIN}/api/v2/users"
    headers = {"Authorization": f"Bearer {token}"}
    users = []
    page = 0
    per_page = 50
    while True:
        params = {"page": page, "per_page": per_page}
        resp = requests.get(url, headers=headers, params=params)
        resp.raise_for_status()
        batch = resp.json()
        if not batch:
            break
        users.extend(batch)
        page += 1
    return users

def update_user_favorites(email: str, favorites: list[str]) -> dict:
    """
    Looks up user by email and updates their app_metadata.favorites.
    """
    ensure_env_loaded()
    token = get_m2m_token()
    AUTH0_DOMAIN = get_env_or_raise("AUTH0_DOMAIN")

    # Step 1: Lookup user by email
    url_lookup = f"https://{AUTH0_DOMAIN}/api/v2/users?q={email}"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url_lookup, headers=headers)
    resp.raise_for_status()
    users = resp.json()
    if not users:
        raise ValueError(f"User with email {email} not found")

    user_id = users[0]["user_id"]

    # Step 2: PATCH favorites to user
    url_patch = f"https://{AUTH0_DOMAIN}/api/v2/users/{user_id}"
    headers["Content-Type"] = "application/json"
    payload = {
        "app_metadata": {
            "favorites": favorites
        }
    }
    patch_resp = requests.patch(url_patch, headers=headers, json=payload)
    patch_resp.raise_for_status()
    return patch_resp.json()
