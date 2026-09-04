"""Conexión a PostgreSQL para el ETL."""
import contextlib

import psycopg2

from etl.config import DB_CONFIG


@contextlib.contextmanager
def get_connection():
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        yield conn
    finally:
        conn.close()
