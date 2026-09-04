"""Carga de configuración del ETL a partir del .env del proyecto."""
from pathlib import Path

from dotenv import load_dotenv
import os

PROJECT_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=PROJECT_ROOT / ".env")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "dbname": os.getenv("DB_NAME", "convenia"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD"),
}

RAW_PATHS = {
    "D1": PROJECT_ROOT / "data" / "raw" / "d1" / "productos" / "d1_raw.json",
    "EXITO": PROJECT_ROOT / "data" / "raw" / "exito" / "productos" / "exito_raw.json",
}
