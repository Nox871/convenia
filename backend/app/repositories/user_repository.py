"""Acceso a datos de usuarios (users).

Un usuario tiene `password_hash`, `google_sub`, o ambos -- nunca ninguno de
los dos (constraint `users_tiene_un_metodo_de_acceso` en la migración
009). `create_user` acepta los dos como opcionales para servir tanto al
registro con correo/contraseña como al primer inicio de sesión con Google.
"""
from sqlalchemy import text
from sqlalchemy.engine import Connection


def create_user(
    conn: Connection,
    email: str,
    password_hash: str | None = None,
    google_sub: str | None = None,
    name: str | None = None,
) -> dict:
    row = conn.execute(
        text(
            """
            INSERT INTO users (email, password_hash, google_sub, name, consent_at)
            VALUES (:email, :password_hash, :google_sub, :name, NOW())
            RETURNING id, email, role, name
            """
        ),
        {"email": email, "password_hash": password_hash, "google_sub": google_sub, "name": name},
    ).mappings().first()
    conn.commit()
    return dict(row)


def get_user_by_email(conn: Connection, email: str) -> dict | None:
    row = conn.execute(
        text("SELECT id, email, password_hash, google_sub, role, name FROM users WHERE email = :email"),
        {"email": email},
    ).mappings().first()
    return dict(row) if row else None


def get_user_by_google_sub(conn: Connection, google_sub: str) -> dict | None:
    row = conn.execute(
        text("SELECT id, email, google_sub, role, name FROM users WHERE google_sub = :google_sub"),
        {"google_sub": google_sub},
    ).mappings().first()
    return dict(row) if row else None


def get_user_by_id(conn: Connection, user_id: int) -> dict | None:
    row = conn.execute(
        text("SELECT id, email, role, name FROM users WHERE id = :id"),
        {"id": user_id},
    ).mappings().first()
    return dict(row) if row else None


def link_google_sub(conn: Connection, user_id: int, google_sub: str) -> None:
    """Asocia una cuenta de Google a un usuario que ya existía por correo y
    contraseña -- para cuando alguien se registró con contraseña y después
    usa 'Iniciar sesión con Google' con el mismo correo."""
    conn.execute(
        text("UPDATE users SET google_sub = :google_sub WHERE id = :id"),
        {"google_sub": google_sub, "id": user_id},
    )
    conn.commit()


def update_user_name(conn: Connection, user_id: int, name: str) -> dict:
    row = conn.execute(
        text("UPDATE users SET name = :name WHERE id = :id RETURNING id, email, role, name"),
        {"name": name, "id": user_id},
    ).mappings().first()
    conn.commit()
    return dict(row)


def set_role(conn: Connection, user_id: int, role: str) -> dict:
    row = conn.execute(
        text("UPDATE users SET role = :role WHERE id = :id RETURNING id, email, role, name"),
        {"role": role, "id": user_id},
    ).mappings().first()
    conn.commit()
    return dict(row)
