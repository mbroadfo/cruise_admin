from fastapi import FastAPI, Request, Response, HTTPException
from app.models import InviteUserRequest, DeleteUserRequest, StandardResponse
from fastapi.middleware.cors import CORSMiddleware
from app.shutdown import monitor_idle_shutdown, update_last_activity_middleware
from admin.auth0_utils import get_all_users, create_user, send_password_reset_email, delete_user, find_user
from admin.token_cache import get_auth0_mgmt_token
import threading
from mangum import Mangum
from typing import Any, Dict, TYPE_CHECKING
import json
import logging

if TYPE_CHECKING:
    from typing import Callable


logger = logging.getLogger()
logger.setLevel(logging.INFO)

app = FastAPI(title="Cruise Admin API", version="0.1.0")

# Allow CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:4173",
        "http://localhost:5173",
        "https://da389rkfiajdk.cloudfront.net",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Start idle shutdown monitor
threading.Thread(target=monitor_idle_shutdown, daemon=True).start()

@app.middleware("http")
async def last_activity_tracker(request: Request, call_next: Callable) -> Response:
    return await update_last_activity_middleware(request, call_next)

@app.middleware("http")
async def log_requests(request: Request, call_next: "Callable") -> Response:
    logger.info(f"Incoming request: {request.method} {request.url.path}")

    response = await call_next(request)

    logger.info(f"Completed {request.method} {request.url.path} with status {response.status_code}")
    return response

@app.get("/admin-api/users", response_model=StandardResponse)
async def list_users_api() -> StandardResponse:
    token = get_auth0_mgmt_token()  # << use the cached token
    users = get_all_users(token)
    return StandardResponse(success=True, message="Users listed successfully", data={"users": users})

@app.post("/admin-api/users", response_model=StandardResponse)
async def invite_user_api(payload: InviteUserRequest) -> StandardResponse:
    token = get_auth0_mgmt_token()  # << use the cached token
    user = find_user(payload.email)

    if user:
        return StandardResponse(success=True, message="User already exists", data={"user_id": user.get("user_id")})

    user = create_user(payload.email, payload.given_name, payload.family_name, token)
    send_password_reset_email(payload.email)
    return StandardResponse(success=True, message="User invited successfully", data={"user_id": user.get("user_id")})

@app.delete("/admin-api/users", response_model=StandardResponse)
async def delete_user_api(payload: DeleteUserRequest) -> StandardResponse:
    user = find_user(payload.email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    delete_user(user.get("user_id"))
    return StandardResponse(success=True, message="User deleted successfully")

handler = Mangum(app)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    logger.info(f"Incoming event: {json.dumps(event)}")

    if event.get("requestContext", {}).get("http", {}).get("method", "") == "OPTIONS":
        logger.info("Handling CORS preflight OPTIONS request")
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "Authorization, Content-Type",
            },
            "body": "",
        }

    response = handler(event, context)

    if isinstance(response, dict) and "headers" in response:
        logger.info(f"Returning response with status: {response.get('statusCode')}")
        response["headers"]["Access-Control-Allow-Origin"] = "*"
        response["headers"]["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
        response["headers"]["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    else:
        logger.warning("Unexpected response type, wrapping manually...")
        response = {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "Authorization, Content-Type",
            },
            "body": json.dumps(response)
        }

    logger.info(f"Final outgoing response: {json.dumps(response)}")
    return response
