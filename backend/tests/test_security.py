import jwt
import pytest

from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)


def test_hash_no_guarda_la_contrasena_en_claro():
    hashed = hash_password("clave-segura-123")
    assert "clave-segura-123" not in hashed
    assert hashed.startswith("$2")  # prefijo de bcrypt


def test_verify_password_acepta_la_correcta_y_rechaza_otra():
    hashed = hash_password("clave-segura-123")
    assert verify_password("clave-segura-123", hashed) is True
    assert verify_password("otra-clave", hashed) is False


def test_dos_hashes_de_la_misma_contrasena_son_distintos():
    assert hash_password("misma") != hash_password("misma")


def test_token_de_acceso_devuelve_el_id_de_usuario():
    assert decode_access_token(create_access_token(42)) == 42


def test_token_manipulado_es_rechazado():
    token = create_access_token(42)
    with pytest.raises(jwt.PyJWTError):
        decode_access_token(token[:-2] + "xx")
