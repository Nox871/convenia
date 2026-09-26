from pydantic import BaseModel, EmailStr, Field


class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, description="Mínimo 8 caracteres")
    name: str = Field(..., min_length=1, max_length=80, description="Nombre y apellido para mostrar")
    accepted_terms: bool = Field(
        ..., description="Aceptó el tratamiento de datos personales; debe ser true para crear la cuenta"
    )


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserUpdate(BaseModel):
    name: str = Field(..., min_length=1, max_length=80, description="Nombre para mostrar")


class GoogleLogin(BaseModel):
    id_token: str = Field(..., description="ID token entregado por Google Sign-In en la app")


class UserPublic(BaseModel):
    id: int
    email: str
    role: str = "user"
    name: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserPublic
