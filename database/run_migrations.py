"""Runner simple de migraciones SQL para Convenia.

No depende de Alembic (el resto del proyecto usa SQL crudo vía psycopg2, ver
etl/db.py) — este script sólo aplica, en orden, los archivos `NNN_*.sql` de
`database/migrations/` que todavía no estén registrados en `schema_migrations`.

Uso:
    python database/run_migrations.py
    python database/run_migrations.py --dry-run   # lista qué se aplicaría, sin ejecutar
"""
from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

import psycopg2

# Permite ejecutar este script directamente (`python database/run_migrations.py`)
# sin depender de que el proyecto esté instalado como paquete: agrega la raíz
# del repo a sys.path para poder importar `etl.config` (mismo patrón usado por
# etl/config.py para su propio .env).
PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from etl.config import DB_CONFIG  # noqa: E402

logger = logging.getLogger("migrations")

MIGRATIONS_DIR = Path(__file__).resolve().parent / "migrations"
CONTROL_MIGRATION = "000_schema_migrations.sql"


def _pending_migrations(conn) -> list[Path]:
    archivos = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not archivos:
        return []

    # La tabla de control puede no existir todavía (primera corrida) -> se
    # aplica siempre primero y de forma incondicional.
    control_path = MIGRATIONS_DIR / CONTROL_MIGRATION
    with conn.cursor() as cur:
        cur.execute(control_path.read_text(encoding="utf-8"))
    conn.commit()

    with conn.cursor() as cur:
        cur.execute("SELECT version FROM schema_migrations")
        aplicadas = {row[0] for row in cur.fetchall()}

    return [
        path
        for path in archivos
        if path.name != CONTROL_MIGRATION and path.name not in aplicadas
    ]


def run_migrations(dry_run: bool = False) -> None:
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        pendientes = _pending_migrations(conn)
        if not pendientes:
            logger.info("No hay migraciones pendientes.")
            return

        for path in pendientes:
            if dry_run:
                logger.info("[dry-run] se aplicaría: %s", path.name)
                continue

            sql = path.read_text(encoding="utf-8")
            logger.info("Aplicando %s ...", path.name)
            try:
                with conn:
                    with conn.cursor() as cur:
                        cur.execute(sql)
                        cur.execute(
                            "INSERT INTO schema_migrations (version) VALUES (%s)",
                            (path.name,),
                        )
            except Exception:
                logger.exception("Falló la migración %s, abortando.", path.name)
                raise
            logger.info("OK: %s", path.name)
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Aplica migraciones SQL de Convenia")
    parser.add_argument("--dry-run", action="store_true", help="Sólo lista qué se aplicaría")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    run_migrations(dry_run=args.dry_run)


if __name__ == "__main__":
    main()
