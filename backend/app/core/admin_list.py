"""Lista de correos que deben ser administradores (ADMIN_EMAILS)."""
from __future__ import annotations


def correos_admin(valor: str | None) -> set[str]:
    """Correos en minúsculas a partir de "a@x.com, B@y.com ;c@z.com"."""
    if not valor:
        return set()
    separados = valor.replace(";", ",").replace("\n", ",").split(",")
    return {c.strip().lower() for c in separados if "@" in c}


def debe_ser_admin(email: str | None, valor_config: str | None) -> bool:
    return bool(email) and email.strip().lower() in correos_admin(valor_config)
