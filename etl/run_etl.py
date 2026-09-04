"""Ejecutor general del ETL.

Uso:
    python -m etl.run_etl D1
    python -m etl.run_etl EXITO
    python -m etl.run_etl ALL
"""
import argparse
import logging

from etl.config import RAW_PATHS
from etl.core import SupermarketETL


def main():
    parser = argparse.ArgumentParser(description="ETL Convenia: RAW -> PostgreSQL")
    parser.add_argument(
        "target",
        choices=["D1", "EXITO", "ALL"],
        type=str.upper,
        help="Qué ETL ejecutar",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    targets = ["D1", "EXITO"] if args.target == "ALL" else [args.target]
    for code in targets:
        SupermarketETL(code=code, raw_path=RAW_PATHS[code]).run()


if __name__ == "__main__":
    main()
