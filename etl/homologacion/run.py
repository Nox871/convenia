"""Homologación: agrupa `source_products` de D1 y Éxito en `products`
canónicos + `product_matches`, cuando hay evidencia real de que son el
mismo producto.

Ejecutar (desde la raíz del proyecto, con el venv del scraper que ya tiene
psycopg2/dotenv):

    python -m etl.homologacion.run

Diseño:
    - Solo evalúa `source_products` SIN match previo (`NOT EXISTS` contra
      `product_matches`), así que reprocesar no duplica nada: cada
      source_product termina con a lo sumo UNA fila en product_matches
      (columna UNIQUE), y cada par ya emparejado no se vuelve a comparar.
    - Solo crea un `products` canónico cuando SÍ aparece un candidato real
      cruzando D1<->Éxito (CONFIRMED o REVIEW). No copia cada
      source_product a products "por si acaso" -- ver README de esta
      carpeta.
    - No genera filas REJECTED masivamente (ver matcher.py): ese status
      queda para cuando una fila REVIEW se descarta explícitamente más
      adelante (paso manual o una futura re-ejecución con mejor señal).

Limitación conocida (documentada, no resuelta en esta primera versión):
    Compara "no resueltos de D1" contra "no resueltos de Éxito" en la MISMA
    corrida. Si más adelante llega un producto nuevo de D1 cuyo par en
    Éxito YA fue homologado en una corrida anterior, esta versión no lo
    intenta enlazar al producto canónico existente (ese candidato ya no
    está "sin resolver"). Para eso haría falta comparar también contra
    `products` ya creados -- una extensión natural, pero fuera de esta
    primera versión para no sobreingenierizar antes de tener datos reales
    de cuántas coincidencias hay siquiera.
"""
from __future__ import annotations

import logging
from collections import defaultdict

from etl import db
from etl.homologacion.matcher import ProductoNormalizado, construir_normalizado, mejor_candidato

import sys
from pathlib import Path

_PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from scraper.core.category_filter import obtener_bucket  # noqa: E402

logger = logging.getLogger("homologacion")


def _cargar_no_resueltos(conn):
    """source_products sin fila en product_matches, con su categoría real."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT sp.id, s.code AS supermarket_code, sp.name_raw, sp.brand_raw,
                   sc.name_raw AS category_name
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            LEFT JOIN source_categories sc ON sc.id = sp.source_category_id
            LEFT JOIN product_matches pm ON pm.source_product_id = sp.id
            WHERE pm.id IS NULL AND sp.is_active = TRUE
            """
        )
        return cur.fetchall()


def _match_method(resultado) -> str:
    señales = ["nombre"]
    if resultado.marca_coincide is not None:
        señales.append("marca")
    if resultado.cantidad_coincide is not None:
        señales.append("cantidad")
    return "+".join(señales)


def _crear_producto(conn, anchor: ProductoNormalizado, categoria_texto: str | None) -> int:
    unidad_por_dimension = {"peso": "g", "volumen": "ml", "conteo": "un"}
    cantidad = anchor.cantidad.valor if anchor.cantidad else None
    unidad = unidad_por_dimension.get(anchor.cantidad.dimension) if anchor.cantidad else None

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO products (name, brand, quantity, unit, category)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
            """,
            (
                anchor.name_raw,
                anchor.marca.title() if anchor.marca else None,
                cantidad,
                unidad,
                categoria_texto,
            ),
        )
        return cur.fetchone()[0]


def _insertar_match(conn, source_product_id: int, product_id: int, method: str,
                     score: float, status: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO product_matches
                (source_product_id, product_id, match_method, confidence_score, status)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (source_product_id) DO NOTHING
            """,
            (source_product_id, product_id, method, round(score, 4), status),
        )


def ejecutar() -> dict:
    stats = {
        "candidatos_d1": 0,
        "candidatos_exito": 0,
        "sin_bucket": 0,
        "products_creados": 0,
        "matches_confirmed": 0,
        "matches_review": 0,
        "sin_candidato": 0,
    }

    with db.get_connection() as conn:
        filas = _cargar_no_resueltos(conn)

        por_bucket_d1 = defaultdict(list)
        por_bucket_exito = defaultdict(list)
        categoria_por_id = {}

        for row in filas:
            sp_id, code, name_raw, brand_raw, category_name = row
            categoria_por_id[sp_id] = category_name

            bucket = obtener_bucket(category_name)
            if bucket is None:
                stats["sin_bucket"] += 1
                continue

            normalizado = construir_normalizado(sp_id, code, name_raw, brand_raw, bucket)

            if code == "D1":
                por_bucket_d1[bucket].append(normalizado)
                stats["candidatos_d1"] += 1
            elif code == "EXITO":
                por_bucket_exito[bucket].append(normalizado)
                stats["candidatos_exito"] += 1

        usados_exito: set[int] = set()

        for bucket, productos_d1 in por_bucket_d1.items():
            candidatos_exito = [
                p for p in por_bucket_exito.get(bucket, [])
                if p.source_product_id not in usados_exito
            ]
            if not candidatos_exito:
                stats["sin_candidato"] += len(productos_d1)
                continue

            for producto_d1 in productos_d1:
                disponibles = [
                    p for p in candidatos_exito
                    if p.source_product_id not in usados_exito
                ]
                resultado_par = mejor_candidato(producto_d1, disponibles)

                if resultado_par is None:
                    stats["sin_candidato"] += 1
                    continue

                candidato, resultado = resultado_par
                usados_exito.add(candidato.source_product_id)

                with conn:
                    categoria_texto = categoria_por_id.get(producto_d1.source_product_id)
                    product_id = _crear_producto(conn, producto_d1, categoria_texto)

                    method = _match_method(resultado)
                    _insertar_match(
                        conn, producto_d1.source_product_id, product_id,
                        method, resultado.score, resultado.status,
                    )
                    _insertar_match(
                        conn, candidato.source_product_id, product_id,
                        method, resultado.score, resultado.status,
                    )

                stats["products_creados"] += 1
                if resultado.status == "CONFIRMED":
                    stats["matches_confirmed"] += 1
                else:
                    stats["matches_review"] += 1

                logger.info(
                    "%s [%s] <-> [%s] %s -> %s (score=%.2f, %s)",
                    bucket,
                    producto_d1.name_raw,
                    candidato.name_raw,
                    "D1/EXITO",
                    resultado.status,
                    resultado.score,
                    resultado.motivo,
                )

    return stats


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    stats = ejecutar()

    print()
    print("HOMOLOGACIÓN")
    print("-" * 40)
    print(f"Candidatos D1 (sin match previo):     {stats['candidatos_d1']}")
    print(f"Candidatos Éxito (sin match previo):  {stats['candidatos_exito']}")
    print(f"Descartados sin bucket de categoría:  {stats['sin_bucket']}")
    print(f"Productos canónicos creados:          {stats['products_creados']}")
    print(f"  - CONFIRMED:                        {stats['matches_confirmed']}")
    print(f"  - REVIEW:                           {stats['matches_review']}")
    print(f"Sin candidato suficientemente bueno:  {stats['sin_candidato']}")
    print("-" * 40)
    print("FINALIZADO")


if __name__ == "__main__":
    main()
