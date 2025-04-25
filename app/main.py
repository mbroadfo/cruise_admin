from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from app.models import InviteUserRequest, DeleteUserRequest, StandardResponse
from app.shutdown import monitor_idle_shutdown, update_last_activity_middleware
from admin.auth0_utils import get_m2m_token, get_all_users, create_user, send_password_reset_email, delete_user, find_user
import threading

app = FastAPI(title="Cruise Admin API", version="0.1.0")

# Start idle shutdown monitor
threading.Thread(target=monitor_idle_shutdown, daemon=True).start()

# Middleware to track last request time
@app.middleware("http")
async def last_activity_tracker(request: Request, call_next):
    return await update_last_activity_middleware(request, call_next)

@app.get("/admin-api/users", response_model=StandardResponse)
async def list_users_api():
    token = get_m2m_token()
    users = get_all_users(token)
    return StandardResponse(success=True, message="Users listed successfully", data={"users": users})

@app.post("/admin-api/users", response_model=StandardResponse)
async def invite_user_api(payload: InviteUserRequest):
    token = get_m2m_token()
    user = find_user(payload.email)

    if user:
        return StandardResponse(success=True, message="User already exists", data={"user_id": user.get("user_id")})

    user = create_user(payload.email, payload.given_name, payload.family_name, token)
    send_password_reset_email(payload.email)
    return StandardResponse(success=True, message="User invited successfully", data={"user_id": user.get("user_id")})

@app.delete("/admin-api/users", response_model=StandardResponse)
async def delete_user_api(payload: DeleteUserRequest):
    user = find_user(payload.email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    delete_user(user.get("user_id"))
    return StandardResponse(success=True, message="User deleted successfully")