import json
from typing import Any, Dict
from admin.auth0_utils import get_m2m_token, get_all_users, create_user, send_password_reset_email, delete_user, find_user

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        route = event.get("rawPath", "")
        method = event.get("requestContext", {}).get("http", {}).get("method", "")

        if route == "/admin-api/users" and method == "GET":
            return list_users()
        elif route == "/admin-api/users" and method == "POST":
            return invite_user(event)
        elif route == "/admin-api/users" and method == "DELETE":
            return delete_user_by_email(event)
        else:
            return {
                "statusCode": 404,
                "body": json.dumps({"error": "Not Found"})
            }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }

def list_users() -> Dict[str, Any]:
    token = get_m2m_token()
    users = get_all_users(token)
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(users)
    }

def invite_user(event: Dict[str, Any]) -> Dict[str, Any]:
    body = json.loads(event.get("body", "{}"))
    email = body.get("email")
    given_name = body.get("given_name")
    family_name = body.get("family_name")

    if not email or not given_name or not family_name:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing required fields"})
        }

    token = get_m2m_token()
    user = find_user(email)

    if user is None:
        user = create_user(email, given_name, family_name, token)
        send_password_reset_email(email)
        return {
            "statusCode": 201,
            "body": json.dumps({"message": "User invited", "user_id": user.get("user_id")})
        }
    else:
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "User already exists", "user_id": user.get("user_id")})
        }

def delete_user_by_email(event: Dict[str, Any]) -> Dict[str, Any]:
    body = json.loads(event.get("body", "{}"))
    email = body.get("email")

    if not email:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Email required"})
        }

    user = find_user(email)
    if user:
        delete_user(user.get("user_id"))
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "User deleted"})
        }
    else:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": "User not found"})
        }
