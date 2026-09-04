"""Motor y conexiones de PostgreSQL para el backend (SQLAlchemy Core, sin ORM).

Se usa SQLAlchemy Core en lugar de mapear modelos ORM porque el esquema ya
existe y es administrado fuera del backend (por las migraciones/objetos que
crearon la base). Las consultas viven en `repositories/` como SQL explícito
parametrizado, lo cual mantiene el mismo estilo que usa el ETL y evita que un
ORM intente "adivinar" o alterar el esquema real.
"""
from sqlalchemy import create_engine
from sqlalchemy.engine import Connection

from app.core.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True, future=True)


def get_db() -> Connection:
    """Dependencia de FastAPI: entrega una conexión por request y la cierra al final."""
    with engine.connect() as connection:
        yield connection
