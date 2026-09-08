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

# Directorio donde cada scraper deja sus snapshots RAW históricos (uno por
# ejecución, nunca se sobrescriben — ver scraper/core/raw_writer.py). El ETL
# resuelve el más reciente de cada directorio en tiempo de ejecución.
RAW_DIRS = {
    "D1": PROJECT_ROOT / "data" / "raw" / "d1" / "productos",
    "EXITO": PROJECT_ROOT / "data" / "raw" / "exito" / "productos",
    "CARULLA": PROJECT_ROOT / "data" / "raw" / "carulla" / "productos",
    "JUMBO": PROJECT_ROOT / "data" / "raw" / "jumbo" / "productos",
    "OLIMPICA": PROJECT_ROOT / "data" / "raw" / "olimpica" / "productos",
}

# Umbrales de negocio configurables por variable de entorno — nunca
# hardcodeados en la lógica de negocio, sin necesidad de una tabla de
# configuración: el resto del proyecto ya se configura por .env.
PRODUCT_DISCONTINUATION_THRESHOLD_DAYS = int(
    os.getenv("PRODUCT_DISCONTINUATION_THRESHOLD_DAYS", "30")
)
# Si un run trae menos que esta fracción del promedio histórico de
# productos detectados, se marca FAILED y NO se aplica ciclo de vida (evita
# descontinuaciones masivas por un scraping roto).
MIN_PRODUCTS_RATIO_VS_HISTORY = float(
    os.getenv("MIN_PRODUCTS_RATIO_VS_HISTORY", "0.5")
)
