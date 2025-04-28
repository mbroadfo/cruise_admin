from fastapi import FastAPI, Request, Response, HTTPException
from app.models import InviteUserRequest, DeleteUserRequest, StandardResponse
from fastapi.middleware.cors import CORSMiddleware
from app.shutdown import monitor_idle_shutdown, update_last_activity_middleware
from admin.auth0_utils import get_all_users, create_user, send_password_reset_email, delete_user, find_user
from admin.token_cache import get_auth0_mgmt_token
import threading
from mangum import Mangum
from typing import Any, Dict, TYPE_CHECKING, TextIO
import json
import logging
import sys
import io
import traceback

if TYPE_CHECKING:
    from typing import Callable

class Unbuffered:
    def __init__(self, stream: TextIO) -> None:
        self.stream = stream

    def write(self, data: str) -> int:
        written = self.stream.write(data)
        self.stream.flush()
        return written

    def flush(self) -> None:
        self.stream.flush()

    def __getattr__(self, name: str) -> object:
        return getattr(self.stream, name)

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

if logger.hasHandlers():
    logger.handlers.clear()

log_handler = logging.StreamHandler(sys.stdout)
log_handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
log_handler.setFormatter(formatter)
logger.addHandler(log_handler)

# Force line-buffering or manually flush
try:
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(line_buffering=True)
    if isinstance(sys.stderr, io.TextIOWrapper):
        sys.stderr.reconfigure(line_buffering=True)
except AttributeError:
    sys.stdout = Unbuffered(sys.stdout)  # type: ignore
    sys.stderr = Unbuffered(sys.stderr)  # type: ignore

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
    # Initialize default response headers
    cors_headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST,DELETE",
        "Access-Control-Allow-Headers": "Authorization,Content-Type"
    }
    
    try:
        logger.info(f"Incoming event: {json.dumps(event, indent=2)}")
        
        # Handle direct invocation (testing)
        if not event.get("requestContext") and not event.get("httpMethod"):
            logger.info("Direct invocation detected")
            return {
                "statusCode": 200,
                "headers": {**cors_headers, "Content-Type": "application/json"},
                "body": json.dumps({
                    "message": "Direct invocation successful",
                    "event": event  # Include event for debugging
                })
            }

        # Handle OPTIONS preflight
        if event.get("httpMethod") == "OPTIONS" or (
            event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS"
        ):
            logger.info("Handling CORS preflight OPTIONS request")
            return {
                "statusCode": 200,
                "headers": cors_headers,
                "body": ""
            }

        # Process regular request
        logger.info("Processing API request")
        response = handler(event, context)
        
        # Ensure response is properly formatted
        if not isinstance(response, dict):
            logger.warning("Received non-dict response from handler")
            response = {
                "statusCode": 200,
                "body": json.dumps(response),
                "headers": {"Content-Type": "application/json"}
            }
        
        # Merge CORS headers
        response.setdefault("headers", {}).update(cors_headers)
        
        logger.info(f"Final response: {json.dumps(response, indent=2)}")
        return response

    except Exception as e:
        logger.error(f"Handler error: {str(e)}\n{traceback.format_exc()}")
        return {
            "statusCode": 500,
            "headers": {**cors_headers, "Content-Type": "application/json"},
            "body": json.dumps({
                "error": str(e),
                "event": event,  # Include the problematic event
                "stacktrace": traceback.format_exc()
            })
        }