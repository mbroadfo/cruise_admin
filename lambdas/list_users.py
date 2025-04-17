import json
from typing import Any, Dict

from admin.auth0_utils import get_m2m_token, get_all_users

def lambda_handler(event: Dict, context: Any) -> Dict[str, Any]:
    try:
        token = get_m2m_token()
        users = get_all_users(token)

        # You can filter/simplify user data here if needed
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(users)
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)})
        }
