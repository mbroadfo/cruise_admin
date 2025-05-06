from fastapi import FastAPI, Request, Response, HTTPException, Query
from app.models import InviteUserRequest, DeleteUserRequest, StandardResponse
from fastapi.middleware.cors import CORSMiddleware
from app.shutdown import monitor_idle_shutdown, update_last_activity_middleware
from admin.auth0_utils import get_all_users, create_user, send_password_reset_email, delete_user, find_user
from admin.token_cache import get_auth0_mgmt_token
from admin.auth0_utils import ensure_env_loaded, update_user_favorites
from app.models import UpdateFavoritesRequest
import threading
from mangum import Mangum
from typing import Any, Dict, TYPE_CHECKING, Callable
import json
import traceback
from contextlib import asynccontextmanager
from typing import AsyncIterator



if TYPE_CHECKING:
    from typing import Callable

@asynccontextmanager
async def app_lifespan(app: FastAPI) -> AsyncIterator[None]:
    # This runs on startup
    ensure_env_loaded()
    yield
    # This runs on shutdown (optional)

# Setup FastAPI
app = FastAPI(title="Cruise Admin API", version="0.1.0", lifespan=app_lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://da389rkfiajdk.cloudfront.net"],  # Use specific origin instead of "*"
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
    print(f"📥 Incoming request: {request.method} {request.url.path}")
    response = await call_next(request)
    print(f"📤 Completed {request.method} {request.url.path} with status {response.status_code}")
    return response

@app.get("/admin-api/users", response_model=StandardResponse)
async def list_users_api() -> StandardResponse:
    ensure_env_loaded()
    token = get_auth0_mgmt_token()
    if token is None:
        raise RuntimeError("❌ Auth0 M2M token is missing")
    users = get_all_users(token)

    return StandardResponse(success=True, message="Users listed successfully", data={"users": users})

@app.post("/admin-api/users", response_model=StandardResponse)
async def invite_user_api(payload: InviteUserRequest) -> StandardResponse:
    ensure_env_loaded()
    token = get_auth0_mgmt_token()
    if token is None:
        raise RuntimeError("❌ Auth0 M2M token is missing")

    existing_user = find_user(payload.email)
    if existing_user:
        return StandardResponse(success=True, message="User already exists", data={"user_id": existing_user.get("user_id")})

    user = create_user(payload.email, payload.given_name, payload.family_name, token)
    send_password_reset_email(payload.email)

    return StandardResponse(success=True, message="User invited successfully", data={"user_id": user.get("user_id")})

@app.delete("/admin-api/users", response_model=StandardResponse)
async def delete_user_api(payload: DeleteUserRequest) -> StandardResponse:
    ensure_env_loaded()
    user = find_user(payload.email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    delete_user(user.get("user_id"))
    return StandardResponse(success=True, message="User deleted successfully")

# Initialize Mangum FIRST
mangum_handler = Mangum(
    app,
    lifespan="off",
    api_gateway_base_path="/prod"  # Add this if using API Gateway stages
)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Your enhanced handler that properly wraps Mangum"""
    # Initialize logging (keep your existing setup)
    print(f"🔥 Lambda handler invoked: {event.get('httpMethod')} {event.get('path')}")

    try:
        # Let Mangum process the request (including OPTIONS)
        response = mangum_handler(event, context)
        
        # Ensure response is properly formatted (Mangum should already do this)
        if not isinstance(response, dict):
            response = {
                "statusCode": 200,
                "body": json.dumps(response),
                "headers": {"Content-Type": "application/json"}
            }

        # Merge headers - preserving Mangum's headers first
        response_headers = response.get("headers", {})
        response["headers"] = {
            **response_headers  # Override with Mangum's headers
        }

        print(f"🥚 Final status: {response['statusCode']}, body: {str(response['body'])[:200]}...")
        return response

    except Exception as e:
        print(f"💥 Handler crashed: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": str(e),
                "stacktrace": traceback.format_exc()
            })
        }
        
@app.get("/admin-api/user", response_model=StandardResponse)
async def get_user_favorites(email: str = Query(...)) -> StandardResponse:
    ensure_env_loaded()
    user = find_user(email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    favorites = user.get("app_metadata", {}).get("favorites", [])
    return StandardResponse(success=True, message="Favorites retrieved", data={"user": {"app_metadata": {"favorites": favorites}}})

@app.patch("/admin-api/user/favorites", response_model=StandardResponse)
async def update_user_favorites_api(payload: UpdateFavoritesRequest) -> StandardResponse:
    try:
        update_user_favorites(payload.email, payload.favorites)
        return StandardResponse(success=True, message="Favorites updated")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update favorites: {str(e)}")
