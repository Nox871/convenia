"""Excepciones de dominio, independientes de FastAPI/HTTP.

Los servicios y repositorios lanzan estas excepciones; main.py las traduce a
respuestas HTTP. Así la capa de negocio no depende del framework web.
"""


class InvalidParameterError(Exception):
    """Parámetros de entrada inválidos -> HTTP 400."""


class NotFoundError(Exception):
    """Recurso solicitado no existe -> HTTP 404."""


class ConflictError(Exception):
    """El recurso ya existe (ej. correo ya registrado) -> HTTP 409."""


class UnauthorizedError(Exception):
    """Credenciales inválidas o token ausente/expirado -> HTTP 401."""


class ForbiddenError(Exception):
    """Identidad válida, pero sin permiso para esta acción -> HTTP 403."""
