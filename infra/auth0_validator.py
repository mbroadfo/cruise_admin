import json
import jwt
import urllib.request
from jwt import PyJWKClient
from urllib.error import URLError

AUTH0_DOMAIN = "dev-jdsnf3lqod8nxlnv.us.auth0.com"
AUTH0_AUDIENCE = "https://dev-jdsnf3lqod8nxlnv.us.auth0.com/api/v2/"
JWKS_URL = f"https://{AUTH0_DOMAIN}/.well-known/jwks.json"

def handler(event, context):
    token = event["authorizationToken"].split(" ")[1]  # "Bearer <token>"

    try:
        jwks_client = PyJWKClient(JWKS_URL)
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        decoded = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=AUTH0_AUDIENCE,
            issuer=f"https://{AUTH0_DOMAIN}/",
        )
        return {
            "principalId": decoded["sub"],
            "policyDocument": {
                "Version": "2012-10-17",
                "Statement": [{
                    "Action": "execute-api:Invoke",
                    "Effect": "Allow",
                    "Resource": event["methodArn"]
                }]
            },
            "context": decoded,
        }

    except Exception as e:
        print(f"JWT validation failed: {str(e)}")
        return {
            "principalId": "unauthorized",
            "policyDocument": {
                "Version": "2012-10-17",
                "Statement": [{
                    "Action": "execute-api:Invoke",
                    "Effect": "Deny",
                    "Resource": event["methodArn"]
                }]
            }
        }
