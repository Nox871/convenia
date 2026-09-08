"""ETL Carulla: RAW -> PostgreSQL. Ejecutar con: python -m etl.etl_carulla"""
import logging

from etl.config import RAW_DIRS
from etl.core import SupermarketETL


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    etl = SupermarketETL(code="CARULLA", raw_dir=RAW_DIRS["CARULLA"])
    etl.run()


if __name__ == "__main__":
    main()
