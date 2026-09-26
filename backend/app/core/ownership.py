"""A quién pertenece una lista.

Sin sesión, la lista pertenece al DISPOSITIVO (`owner_ref` = un UUID que la app
genera). Con sesión iniciada pertenece a la CUENTA, con el dueño
`user:<id>` que decide el servidor a partir del token -- nunca el cliente, para
que nadie pueda pedir las listas de otra persona.
"""
from __future__ import annotations

from app.core.exceptions import ForbiddenError

USER_PREFIX = "user:"


def account_owner_ref(user_id: int) -> str:
    return f"{USER_PREFIX}{user_id}"


def resolve_owner_ref(device_ref: str, user_id: int | None) -> str:
    """Dueño efectivo de las listas de esta petición."""
    if user_id is not None:
        return account_owner_ref(user_id)
    if device_ref.startswith(USER_PREFIX):
        # Un invitado no puede hacerse pasar por una cuenta enviando "user:5".
        raise ForbiddenError("Identificador de dispositivo inválido")
    return device_ref


def user_id_from_owner_ref(owner_ref: str) -> int | None:
    """Id de la cuenta si el dueño es una cuenta; `None` si es un dispositivo."""
    if not owner_ref.startswith(USER_PREFIX):
        return None
    try:
        return int(owner_ref[len(USER_PREFIX):])
    except ValueError:
        return None
