import os
from admin.aws_secrets import inject_env_from_secrets

# Load secrets only ONCE, lazily
SECRET_NAME = os.getenv("AWS_SECRET_NAME", "cruise-finder-secrets")
REGION_NAME = os.getenv("AWS_REGION", "us-west-2")

# Inject secrets into environment
inject_env_from_secrets(SECRET_NAME, REGION_NAME)

# Now you can safely grab them
AUTH0_DOMAIN = os.getenv("AUTH0_DOMAIN")
AUTH0_CLIENT_ID = os.getenv("AUTH0_CLIENT_ID")
AUTH0_CLIENT_SECRET = os.getenv("AUTH0_CLIENT_SECRET")
AUTH0_WEB_CLIENT_ID = os.getenv("AUTH0_WEB_CLIENT_ID")
AUTH0_CONNECTION = os.getenv("AUTH0_CONNECTION", "Username-Password-Authentication")
CLOUD_FRONT_URI = os.getenv("CLOUD_FRONT_URI")
REDIRECT_URI = os.getenv("REDIRECT_URI")