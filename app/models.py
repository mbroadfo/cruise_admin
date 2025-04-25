from pydantic import BaseModel, EmailStr

class InviteUserRequest(BaseModel):
    email: EmailStr
    given_name: str
    family_name: str

class DeleteUserRequest(BaseModel):
    email: EmailStr

class StandardResponse(BaseModel):
    success: bool
    message: str
    data: dict | None = None