import threading
import time
import os
from datetime import datetime, timedelta

last_request_time = datetime.utcnow()

def monitor_idle_shutdown(idle_minutes=10):
    while True:
        now = datetime.utcnow()
        if (now - last_request_time) > timedelta(minutes=idle_minutes):
            print(f"💤 Idle timeout reached ({idle_minutes} min). Shutting down.")
            os._exit(0)
        time.sleep(60)

async def update_last_activity_middleware(request, call_next):
    global last_request_time
    last_request_time = datetime.utcnow()
    response = await call_next(request)
    return response