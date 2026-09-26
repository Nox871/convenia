"""Lógica de negocio de registro e inicio de sesión."""
from __future__ import annotations

import logging

from google.auth.exceptions import GoogleAuthError
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from jwt import PyJWTError
from sqlalchemy.engine import Connection

from app.core.config import settings
from app.core.exceptions import ConflictError, InvalidParameterError, UnauthorizedError
from app.core.security import create_access_token, decode_access_token, hash_password, verify_password
from app.repositories import user_repository
from app.schemas.auth import TokenResponse, UserPublic

logger = logging.getLogger("app.services.auth")

_google_request = google_requests.Request()


def register(
    conn: Connection, email: str, password: str, name: str | None = None, accepted_terms: bool = False
) -> TokenResponse:
    if not accepted_terms:
        raise InvalidParameterError(
            "Debes aceptar el tratamiento de datos personales para crear la cuenta"
        )
    # Normalizado a minúsculas para que "Ana@x.com" y "ana@x.com" sean la
    # misma cuenta -- el correo no distingue mayúsculas en la práctica.
    email = email.strip().lower()

    existing = user_repository.get_user_by_email(conn, email)
    if existing is not None:
        raise ConflictError(f"Ya existe una cuenta con el correo '{email}'")

    clean_name = name.strip() if name else None
    user = user_repository.create_user(
        conn, email=email, password_hash=hash_password(password), name=clean_name or None
    )
    token = create_access_token(user["id"])
    return TokenResponse(access_token=token, user=UserPublic(**user))


def login(conn: Connection, email: str, password: str) -> TokenResponse:
    email = email.strip().lower()
    user = user_repository.get_user_by_email(conn, email)
    # Mismo mensaje de error si el correo no existe o si la contraseña no
    # coincide -- distinguirlos le confirmaría a un atacante qué correos
    # están registrados en el sistema.
    if user is None or user["password_hash"] is None:
        raise UnauthorizedError("Correo o contraseña incorrectos")
    if not verify_password(password, user["password_hash"]):
        raise UnauthorizedError("Correo o contraseña incorrectos")

    token = create_access_token(user["id"])
    return TokenResponse(access_token=token, user=UserPublic(id=user["id"], email=user["email"], role=user["role"], name=user["name"]))


def login_with_google(conn: Connection, google_id_token_str: str) -> TokenResponse:
    """Verifica el ID token que entrega Google Sign-In en la app, y crea o
    encuentra al usuario correspondiente. Nunca se guarda ni se maneja una
    contraseña para este camino -- Google ya verificó la identidad; el
    backend sólo comprueba que la firma del token es real y que fue
    emitido para ESTA aplicación (el `audience` debe ser el Client ID web
    configurado), no para otra."""
    try:
        claims = google_id_token.verify_oauth2_token(
            google_id_token_str, _google_request, settings.google_web_client_id
        )
    except (GoogleAuthError, ValueError) as exc:
        # Se registra el motivo real (audiencia, reloj, firma...) sin el token.
        logger.warning("Verificación del token de Google falló: %s", exc)
        raise UnauthorizedError("Token de Google inválido") from exc

    google_sub = claims["sub"]
    email = claims.get("email")
    if not email:
        raise InvalidParameterError("La cuenta de Google no tiene un correo asociado")
    email = email.strip().lower()
    google_name = (claims.get("name") or "").strip() or None

    user = user_repository.get_user_by_google_sub(conn, google_sub)
    if user is None:
        # ¿Ya existía una cuenta con este correo (registrada con
        # contraseña)? Se enlaza en vez de crear una cuenta duplicada.
        existing = user_repository.get_user_by_email(conn, email)
        if existing is not None:
            user_repository.link_google_sub(conn, existing["id"], google_sub)
            user = {"id": existing["id"], "email": existing["email"], "role": existing["role"], "name": existing["name"]}
        else:
            user = user_repository.create_user(conn, email=email, google_sub=google_sub, name=google_name)

    # Si la cuenta aún no tiene nombre, se completa con el de Google (nunca
    # se pisa uno que el usuario ya haya editado).
    if user.get("name") is None and google_name:
        user = user_repository.update_user_name(conn, user["id"], google_name)

    token = create_access_token(user["id"])
    return TokenResponse(
        access_token=token,
        user=UserPublic(id=user["id"], email=user["email"], role=user["role"], name=user.get("name")),
    )


def update_name(conn: Connection, user_id: int, name: str) -> UserPublic:
    clean = name.strip()
    if not clean:
        raise InvalidParameterError("El nombre no puede estar vacío")
    return UserPublic(**user_repository.update_user_name(conn, user_id, clean))


def get_current_user(conn: Connection, token: str) -> UserPublic:
    try:
        user_id = decode_access_token(token)
    except PyJWTError as exc:
        raise UnauthorizedError("Token inválido o expirado") from exc

    user = user_repository.get_user_by_id(conn, user_id)
    if user is None:
        raise UnauthorizedError("El usuario de este token ya no existe")
    return UserPublic(**user)
