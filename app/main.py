from fastapi import FastAPI, Request, Response, HTTPException
from app.models import InviteUserRequest, DeleteUserRequest, StandardResponse
from fastapi.middleware.cors import CORSMiddleware
from app.shutdown import monitor_idle_shutdown, update_last_activity_middleware
from admin.auth0_utils import get_all_users, create_user, send_password_reset_email, delete_user, find_user
from admin.token_cache import get_auth0_mgmt_token
import threading
from mangum import Mangum
from typing import Any, Dict, TYPE_CHECKING, Callable
import json
import logging
import sys
import traceback


if TYPE_CHECKING:
    from typing import Callable

# Clear any existing handlers
log_root = logging.getLogger()
if log_root.handlers:
    for log_handler in log_root.handlers:
        log_root.removeHandler(log_handler)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),  # Sends to CloudWatch
        logging.StreamHandler(sys.stderr)   # Duplicate to stderr for safety
    ]
)
logger = logging.getLogger(__name__)

# Force immediate flush
logger.handlers[0].flush()

app = FastAPI(title="Cruise Admin API", version="0.1.0")

# Allow CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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
async def log_requests(request: Request, call_next: Callable) -> Response:
    logger.info(f"📥 Incoming request: {request.method} {request.url.path}")
    response = await call_next(request)
    logger.info(f"📤 Completed {request.method} {request.url.path} with status {response.status_code}")
    return response

@app.get("/admin-api/users", response_model=StandardResponse)
async def list_users_api() -> StandardResponse:
    token = get_auth0_mgmt_token()
    users = get_all_users(token)
    return StandardResponse(success=True, message="Users listed successfully", data={"users": users})

@app.post("/admin-api/users", response_model=StandardResponse)
async def invite_user_api(payload: InviteUserRequest) -> StandardResponse:
    token = get_auth0_mgmt_token()
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
    # Initialize logging first
    logger.info("🔵 Lambda invocation started")
    logger.debug(f"Raw event: {json.dumps(event, indent=2)}")
    
    # Define CORS headers (moved to top)
    cors_headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST,DELETE", 
        "Access-Control-Allow-Headers": "Authorization,Content-Type"
    }

    try:
        logger.info("📥 Processing request...")
        
        # Handle OPTIONS preflight
        if event.get("httpMethod") == "OPTIONS":
            logger.info("Handling OPTIONS preflight")
            return {
                "statusCode": 200,
                "headers": cors_headers,
                "body": ""
            }

        # Process regular request through Mangum
        response = handler(event, context)
        logger.info(f"📤 Handler response: {json.dumps(response, indent=2)}")
        
        # Ensure proper response format
        if not isinstance(response, dict):
            logger.warning("Received non-dict response from handler")
            response = {
                "statusCode": 200,
                "body": json.dumps(response),
                "headers": {"Content-Type": "application/json"}
            }
        
        # Merge headers (preserve existing headers from handler)
        final_headers = {
            "Content-Type": "application/json",
            **cors_headers,
            **response.get("headers", {})
        }

        return {
            "statusCode": response.get("statusCode", 200),
            "headers": final_headers,
            "body": response.get("body", "")
        }

    except Exception as e:
        logger.exception(f"💥 Handler crashed: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {**cors_headers, "Content-Type": "application/json"},
            "body": json.dumps({
                "error": str(e),
                "stacktrace": traceback.format_exc()
            })
        }