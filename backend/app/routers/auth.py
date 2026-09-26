from fastapi import APIRouter, Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.core.exceptions import ForbiddenError
from app.schemas.auth import GoogleLogin, TokenResponse, UserLogin, UserPublic, UserRegister, UserUpdate
from app.services import auth_service

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

_bearer_scheme = HTTPBearer()
_optional_bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    conn: Connection = Depends(get_db),
) -> UserPublic:
    """Dependencia de FastAPI para proteger un endpoint: exige el header
    `Authorization: Bearer <token>` y devuelve el usuario dueño del token,
    o responde 401 automáticamente si falta, es inválido o ya expiró."""
    return auth_service.get_current_user(conn, credentials.credentials)


def get_optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_optional_bearer_scheme),
    conn: Connection = Depends(get_db),
) -> UserPublic | None:
    """Como `get_current_user`, pero sin sesión devuelve `None` en vez de 401:
    para endpoints que funcionan tanto para invitados como para cuentas. Un
    token presente pero inválido sí responde 401."""
    if credentials is None:
        return None
    return auth_service.get_current_user(conn, credentials.credentials)


def require_admin(current_user: UserPublic = Depends(get_current_user)) -> UserPublic:
    """Como `get_current_user`, pero además exige rol 'admin' -- para
    acciones que un usuario común no debe poder hacer, como agregar
    establecimientos físicos manualmente."""
    if current_user.role != "admin":
        raise ForbiddenError("Esta acción requiere una cuenta de administrador")
    return current_user


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(payload: UserRegister, conn: Connection = Depends(get_db)):
    return auth_service.register(
        conn,
        email=payload.email,
        password=payload.password,
        name=payload.name,
        accepted_terms=payload.accepted_terms,
    )


@router.post("/login", response_model=TokenResponse)
def login(payload: UserLogin, conn: Connection = Depends(get_db)):
    return auth_service.login(conn, email=payload.email, password=payload.password)


@router.post("/google", response_model=TokenResponse)
def google_login(payload: GoogleLogin, conn: Connection = Depends(get_db)):
    return auth_service.login_with_google(conn, payload.id_token)


@router.get("/me", response_model=UserPublic)
def me(current_user: UserPublic = Depends(get_current_user)):
    return current_user


@router.put("/me", response_model=UserPublic)
def update_me(
    payload: UserUpdate,
    current_user: UserPublic = Depends(get_current_user),
    conn: Connection = Depends(get_db),
):
    return auth_service.update_name(conn, current_user.id, payload.name)
