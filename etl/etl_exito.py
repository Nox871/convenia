"""ETL Éxito: RAW -> PostgreSQL. Ejecutar con: python -m etl.etl_exito"""
import logging

from etl.config import RAW_PATHS
from etl.core import SupermarketETL


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    etl = SupermarketETL(code="EXITO", raw_path=RAW_PATHS["EXITO"])
    etl.run()


if __name__ == "__main__":
    main()
