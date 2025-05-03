from pydantic import BaseModel, EmailStr
from typing import List

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
    
class UpdateFavoritesRequest(BaseModel):
    email: EmailStr
    favorites: List[str]
