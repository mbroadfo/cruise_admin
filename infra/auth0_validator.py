import json
import jwt
import urllib.request
from jwt import PyJWKClient
from urllib.error import URLError

AUTH0_DOMAIN = "dev-jdsnf3lqod8nxlnv.us.auth0.com"
AUTH0_AUDIENCE = "https://cruise-admin-api"
JWKS_URL = f"https://{AUTH0_DOMAIN}/.well-known/jwks.json"

def handler(event, context):
    print("🔍 Incoming event:")
    print(json.dumps(event, indent=2))

    try:
        if "authorizationToken" not in event:
            raise ValueError("Missing 'authorizationToken' in event")

        token = event["authorizationToken"].split(" ")[1]  # "Bearer <token>"

        jwks_client = PyJWKClient(JWKS_URL)
        signing_key = jwks_client.get_signing_key_from_jwt(token)

        decoded = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=AUTH0_AUDIENCE,
            issuer=f"https://{AUTH0_DOMAIN}/",
        )

        print("✅ Token validated successfully")
        sanitized_context = {
            k: str(v)
            for k, v in decoded.items()
            if isinstance(v, (str, int, float, bool))
        }

        return {
            "principalId": decoded["sub"],
            "policyDocument": {
                "Version": "2012-10-17",
                "Statement": [{
                    "Action": "execute-api:Invoke",
                    "Effect": "Allow",
                    "Resource": event["methodArn"].rsplit("/", 1)[0] + "/*"
                }]
            },
            "context": sanitized_context,
        }


    except Exception as e:
        print(f"❌ JWT validation failed: {str(e)}")
        return {
            "principalId": "unauthorized",
            "policyDocument": {
                "Version": "2012-10-17",
                "Statement": [{
                    "Action": "execute-api:Invoke",
                    "Effect": "Deny",
                    "Resource": event.get("methodArn", "*")
                }]
            }
        }
