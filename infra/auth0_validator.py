import json
import jwt
import urllib.request
from jwt import PyJWKClient
from urllib.error import URLError

AUTH0_DOMAIN = "dev-jdsnf3lqod8nxlnv.us.auth0.com"
AUTH0_AUDIENCE_PERMISSIONS = {
    "https://cruise-admin-api": "app_metadata:role:admin",
    "https://cruise-viewer-api": "*"
}
JWKS_URL = f"https://{AUTH0_DOMAIN}/.well-known/jwks.json"
algorithms = ["RS256"]


def handler(event, context):
    print("🔍 Incoming event:")
    print(json.dumps(event, indent=2))

    try:
        if "authorizationToken" not in event:
            raise ValueError("Missing 'authorizationToken' in event")

        token = event["authorizationToken"].split(" ")[1]  # "Bearer <token>"

        jwks_client = PyJWKClient(JWKS_URL)
        signing_key = jwks_client.get_signing_key_from_jwt(token)

        decoded = jwt.decode(token, signing_key.key, options={"verify_aud": False}, algorithms=algorithms)

        # Manually check audience match
        token_aud = decoded.get("aud")
        if isinstance(token_aud, str):
            token_aud = [token_aud]

        allowed = False
        for aud in token_aud:
            required = AUTH0_AUDIENCE_PERMISSIONS.get(aud)
            if not required:
                continue  # Unknown audience

            if required == "*" or required in decoded.get("permissions", []):
                allowed = True
                break

        if not allowed:
            raise Exception("User lacks required role or permission for audience")

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
            "context": {}, # Optional
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
