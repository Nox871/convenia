"""ETL D1: RAW -> PostgreSQL. Ejecutar con: python -m etl.etl_d1"""
import logging

from etl.config import RAW_PATHS
from etl.core import SupermarketETL


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    etl = SupermarketETL(code="D1", raw_path=RAW_PATHS["D1"])
    etl.run()


if __name__ == "__main__":
    main()
