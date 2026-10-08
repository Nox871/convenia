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
    parser.add_argument(
        "--aceptar-tamano",
        action="store_true",
        help="CARGA MANUAL: acepta un RAW mucho más pequeño que el histórico (úsalo sólo "
        "tras confirmar que la caída es legítima)",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    targets = SUPERMARKET_CODES if args.target == "ALL" else [args.target]
    log = logging.getLogger("etl")
    fallidos: list[str] = []
    for code in targets:
        # Una tienda con datos malos (p. ej. un scraper que trajo la cuarta parte del
        # catálogo y el ETL se niega a cargarlo) NO debe impedir cargar las demás.
        try:
            SupermarketETL(code=code, raw_dir=RAW_DIRS[code], aceptar_tamano=args.aceptar_tamano).run()
        except Exception:  # noqa: BLE001 - se registra con traza y se sigue
            log.exception("ETL %s FALLÓ; se continúa con las demás tiendas", code)
            fallidos.append(code)
    if fallidos:
        log.error("ETL terminado con fallos en: %s", ", ".join(fallidos))
        raise SystemExit(1)  # que la corrida diaria lo marque en el correo


if __name__ == "__main__":
    main()
