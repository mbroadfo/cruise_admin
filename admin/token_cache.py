import os
import time
import requests
import boto3
import json
from typing import Optional, Tuple
from botocore.exceptions import ClientError

# Memory cache (fastest - survives Lambda warm starts)
_auth0_mgmt_token: Optional[str] = None
_auth0_mgmt_token_expiry: float = 0.0

# Configuration
TOKEN_CACHE_SECONDS = 24 * 60 * 60  # 24 hours
PARAMETER_STORE_TOKEN_PATH = "/cruise-admin/prod/auth0-mgmt-token"
TOKEN_EXPIRY_BUFFER = 300  # 5 minutes buffer before expiry

def get_env_or_raise(name: str) -> str:
    """Get environment variable or raise error if not set."""
    val = os.getenv(name)
    if not val:
        raise RuntimeError(f"{name} is not set in the environment")
    return val


def _save_token_to_parameter_store(token: str, expiry: float, region_name: str = "us-west-2") -> None:
    """
    Save Auth0 token and expiry to Parameter Store (Tier 2 cache).
    
    Stores as JSON: {"token": "...", "expiry": 1234567890.0}
    """
    try:
        client = boto3.client("ssm", region_name=region_name)
        cache_data = json.dumps({"token": token, "expiry": expiry})
        
        client.put_parameter(
            Name=PARAMETER_STORE_TOKEN_PATH,
            Value=cache_data,
            Type="SecureString",
            Overwrite=True,
            Description="Cached Auth0 Management API token"
        )
        print(f"💾 Saved token to Parameter Store (expires: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(expiry))})")
    except ClientError as e:
        print(f"⚠️  Failed to save token to Parameter Store: {e}")
        # Non-fatal - continue without Parameter Store cache


def _load_token_from_parameter_store(region_name: str = "us-west-2") -> Optional[Tuple[str, float]]:
    """
    Load Auth0 token from Parameter Store (Tier 2 cache).
    
    Returns: (token, expiry) tuple or None if not found/expired
    """
    try:
        client = boto3.client("ssm", region_name=region_name)
        response = client.get_parameter(Name=PARAMETER_STORE_TOKEN_PATH, WithDecryption=True)
        
        cache_data = json.loads(response['Parameter']['Value'])
        token = cache_data.get("token")
        expiry = cache_data.get("expiry", 0.0)
        
        now = time.time()
        if token and expiry > now + TOKEN_EXPIRY_BUFFER:
            remaining = int((expiry - now) / 60)
            print(f"📦 Loaded token from Parameter Store ({remaining} min remaining)")
            return (token, expiry)
        else:
            print(f"⏰ Parameter Store token expired or expiring soon")
            return None
            
    except ClientError as e:
        if e.response['Error']['Code'] == 'ParameterNotFound':
            print(f"📭 No cached token in Parameter Store")
        else:
            print(f"⚠️  Failed to load token from Parameter Store: {e}")
        return None


def _fetch_new_token_from_auth0() -> Tuple[str, float]:
    """
    Fetch a new Auth0 Management API token (Tier 3 - slowest).
    
    Returns: (token, expiry) tuple
    """
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

    print(f"🔑 Fetching new token from Auth0...")
    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()
    data = response.json()

    token = data["access_token"]
    now = time.time()
    expiry = now + TOKEN_CACHE_SECONDS - TOKEN_EXPIRY_BUFFER
    
    print(f"✅ New token fetched from Auth0 (valid for {TOKEN_CACHE_SECONDS/3600:.1f} hours)")
    return (token, expiry)


def get_auth0_mgmt_token() -> str:
    """
    Get Auth0 Management API token using three-tier caching:
    
    1. Memory cache (in-process) - fastest, survives warm Lambda starts
    2. Parameter Store (cross-invocation) - medium speed, shared across instances
    3. Auth0 API (network call) - slowest, only when caches miss
    
    Returns: Valid Auth0 Management API access token
    """
    global _auth0_mgmt_token, _auth0_mgmt_token_expiry

    now = time.time()
    region_name = os.getenv("AWS_REGION", "us-west-2")

    # Tier 1: Check memory cache (fastest)
    if _auth0_mgmt_token and _auth0_mgmt_token_expiry > now + TOKEN_EXPIRY_BUFFER:
        remaining = int((_auth0_mgmt_token_expiry - now) / 60)
        print(f"⚡ Using memory-cached token ({remaining} min remaining)")
        return _auth0_mgmt_token

    print(f"🔍 Memory cache miss, checking Parameter Store...")

    # Tier 2: Check Parameter Store cache
    cached_token = _load_token_from_parameter_store(region_name)
    if cached_token:
        token, expiry = cached_token
        # Update memory cache
        _auth0_mgmt_token = token
        _auth0_mgmt_token_expiry = expiry
        return token

    # Tier 3: Fetch new token from Auth0
    token, expiry = _fetch_new_token_from_auth0()
    
    # Update both caches
    _auth0_mgmt_token = token
    _auth0_mgmt_token_expiry = expiry
    _save_token_to_parameter_store(token, expiry, region_name)
    
    return token
