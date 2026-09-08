"""Ejecutor general del ETL.

Uso:
    python -m etl.run_etl D1
    python -m etl.run_etl EXITO
    python -m etl.run_etl CARULLA
    python -m etl.run_etl JUMBO
    python -m etl.run_etl OLIMPICA
    python -m etl.run_etl ALL
"""
import argparse
import logging

from etl.config import RAW_DIRS
from etl.core import SupermarketETL

SUPERMARKET_CODES = ["D1", "EXITO", "CARULLA", "JUMBO", "OLIMPICA"]


def main():
    parser = argparse.ArgumentParser(description="ETL Convenia: RAW -> PostgreSQL")
    parser.add_argument(
        "target",
        choices=[*SUPERMARKET_CODES, "ALL"],
        type=str.upper,
        help="Qué ETL ejecutar",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    targets = SUPERMARKET_CODES if args.target == "ALL" else [args.target]
    for code in targets:
        SupermarketETL(code=code, raw_dir=RAW_DIRS[code]).run()


if __name__ == "__main__":
    main()
