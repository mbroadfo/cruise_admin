from setuptools import setup, find_packages

setup(
    name="cruise-admin",
    version="0.1.0",
    description="CLI tool for managing Auth0 users in the Lindblad Cruise Viewer.",
    author="Mike Broadfoot",
    packages=find_packages(),
    install_requires=[
        "click",
        "requests",
        "boto3",
    ],
    entry_points={
        "console_scripts": [
            "cruise-admin=admin.auth0_cli:cli",
        ],
    },
    python_requires=">=3.8",
    include_package_data=True,
)
