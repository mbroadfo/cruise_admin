import time
import os
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import Request, Response
    from typing import Callable
    

last_request_time = datetime.now(timezone.utc)

def monitor_idle_shutdown(idle_minutes: int = 10) -> None:
    while True:
        now = datetime.now(timezone.utc)
        if (now - last_request_time) > timedelta(minutes=idle_minutes):
            print(f"💤 Idle timeout reached ({idle_minutes} min). Shutting down.")
            os._exit(0)
        time.sleep(60)

async def update_last_activity_middleware(request: "Request", call_next: "Callable") -> "Response":
    global last_request_time
    last_request_time = datetime.now(timezone.utc)
    response = await call_next(request)
    return response