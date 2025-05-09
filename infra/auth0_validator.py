import json
import jwt
from jwt import PyJWKClient
from typing import Any, Dict

AUTH0_DOMAIN = "dev-jdsnf3lqod8nxlnv.us.auth0.com"
AUTH0_AUDIENCE_PERMISSIONS = {
    "https://cruise-admin-api": "admin",
    "https://cruise-viewer-api": "*"
}
JWKS_URL = f"https://{AUTH0_DOMAIN}/.well-known/jwks.json"
ALGORITHMS = ["RS256"]

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    print("🔍 Incoming event:")
    print(json.dumps(event, indent=2))

    try:
        if "authorizationToken" not in event:
            raise ValueError("Missing 'authorizationToken' in event")

        token = event["authorizationToken"].split(" ")[1]  # "Bearer <token>"

        jwks_client = PyJWKClient(JWKS_URL)
        signing_key = jwks_client.get_signing_key_from_jwt(token)

        decoded = jwt.decode(token, signing_key.key, options={"verify_aud": False}, algorithms=ALGORITHMS)

        print("✅ Decoded JWT:")
        print(json.dumps(decoded, indent=2))

        # Manually check audience match
        token_aud = decoded.get("aud")
        if isinstance(token_aud, str):
            token_aud = [token_aud]

        if not token_aud:
            raise Exception("Missing audience claim")

        print(f"🎯 Token audiences: {token_aud}")

        allowed = False
        for aud in token_aud:
            required = AUTH0_AUDIENCE_PERMISSIONS.get(aud)
            print(f"🔍 Checking audience: {aud}, required role: {required}")
            if not required:
                continue  # Unknown audience

            if required == "*":
                allowed = True
                break
            elif required == "admin":
                if decoded.get("gty") == "client-credentials":
                    print("🔓 Token is from client credentials grant, bypassing role check.")
                    allowed = True
                    break

                roles_claim = decoded.get("https://cruise-viewer.app/roles")
                print(f"👥 Found roles claim: {roles_claim}")
                roles = []

                if isinstance(roles_claim, dict):
                    roles = roles_claim.get("role", [])
                elif isinstance(roles_claim, list):
                    roles = roles_claim
                elif isinstance(roles_claim, str):
                    roles = [roles_claim]

                print(f"🔑 Normalized roles: {roles}")
                if "admin" in roles:
                    print("✅ User has admin role")
                    allowed = True
                    break

        if not allowed:
            raise Exception("User not authorized for this audience")

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
            "context": {},
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
