def test_patch_user_favorites_success():
    from app.main import app
    from fastapi.testclient import TestClient
    import os
    import json

    client = TestClient(app)

    token = os.getenv("AUTH0_MGMT_API_TOKEN")  # Must be valid
    test_email = os.getenv("TEST_USER_EMAIL", "tebzxq34f@mozmail.com")

    patch_response = client.patch(
        "/admin-api/user/favorites",
        headers={"Authorization": f"Bearer {token}"},
        json={"email": test_email, "favorites": ["X123", "Y456"]}
    )

    print("🔍 Response status:", patch_response.status_code)
    print("📦 Response body:", patch_response.text)

    assert patch_response.status_code == 200

    print("✅ Patch response:", patch_response.json())

    # Now fetch user profile
    from admin.auth0_utils import find_user
    user = find_user(test_email)

    favorites = user.get("app_metadata", {}).get("favorites", [])
    print("📄 Updated favorites:", favorites)

    assert "X123" in favorites
    assert "Y456" in favorites
