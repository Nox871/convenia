"""Contraseñas y tokens de sesión.

Las contraseñas nunca se guardan ni se manejan en texto plano más allá del
momento en que llegan en el request: `hash_password` las convierte de
inmediato en un hash de `bcrypt`, un proceso de una sola vía. No es
cifrado -- no existe una llave que revierta un hash de bcrypt a la
contraseña original, ni siquiera para quien tenga acceso directo a la
base de datos.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from app.core.config import settings


def hash_password(password: str) -> str:
    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    return hashed.decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def create_access_token(user_id: int) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(hours=settings.jwt_expiration_hours),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> int:
    """Devuelve el `user_id` del token, o lanza `jwt.PyJWTError` si el token
    es inválido, fue alterado, o ya expiró -- el router lo traduce a 401."""
    payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    return int(payload["sub"])
