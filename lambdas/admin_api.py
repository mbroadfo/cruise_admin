# File: lambdas/admin_api.py

import json
from admin.auth0_utils import (
    get_m2m_token,
    list_users as list_all_users,
    find_user,
    create_user,
    send_password_reset_email,
    delete_user
)

def lambda_handler(event, context):
    try:
        method = event.get("httpMethod")
        path = event.get("path")

        if path == "/users" and method == "GET":
            return list_users()
        elif path == "/users" and method == "POST":
            return invite_user(json.loads(event.get("body", "{}")))
        elif path == "/users" and method == "DELETE":
            return delete_user_by_email(json.loads(event.get("body", "{}")))
        else:
            return response(404, {"error": "Not found"})

    except Exception as e:
        return response(500, {"error": str(e)})

def list_users():
    token = get_m2m_token()
    users = list_all_users(token)
    return response(200, users)

def invite_user(data):
    required_fields = ["email", "given_name", "family_name"]
    if not all(field in data for field in required_fields):
        return response(400, {"error": "Missing required fields"})

    token = get_m2m_token()
    user = find_user(data["email"])

    if not user:
        user = create_user(data["email"], data["given_name"], data["family_name"], token)
        send_password_reset_email(data["email"])
        return response(201, {"message": "User invited", "user_id": user.get("user_id")})
    else:
        return response(200, {"message": "User already exists", "user_id": user.get("user_id")})

def delete_user_by_email(data):
    email = data.get("email")
    if not email:
        return response(400, {"error": "Missing email"})

    user = find_user(email)
    if not user:
        return response(404, {"error": "User not found"})

    delete_user(user["user_id"])
    return response(200, {"message": f"User {email} deleted"})

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }