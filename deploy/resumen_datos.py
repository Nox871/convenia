"""Texto para el correo diario: cuántos productos con precio de hoy tiene cada
tienda y si alguna cayó respecto a su promedio de los 7 días anteriores.
Nunca falla la corrida: si algo sale mal, imprime el motivo y termina."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

SQL = """
WITH por_dia AS (
    SELECT s.name AS tienda,
           (po.observed_at AT TIME ZONE 'America/Bogota')::date AS dia,
           COUNT(DISTINCT po.source_product_id) AS n
    FROM price_observations po
    JOIN source_products sp ON sp.id = po.source_product_id
    JOIN supermarkets s ON s.id = sp.supermarket_id
    WHERE po.observed_at >= now() - interval '9 days'
    GROUP BY 1, 2
), hoy AS (
    SELECT tienda, n FROM por_dia WHERE dia = (now() AT TIME ZONE 'America/Bogota')::date
), antes AS (
    SELECT tienda, AVG(n) AS prom FROM por_dia
    WHERE dia < (now() AT TIME ZONE 'America/Bogota')::date GROUP BY 1
)
SELECT a.tienda, COALESCE(h.n, 0), a.prom
FROM antes a LEFT JOIN hoy h USING (tienda) ORDER BY a.tienda
"""


def main() -> int:
    try:
        from etl import db

        with db.get_connection() as conn, conn.cursor() as cur:
            cur.execute(SQL)
            filas = cur.fetchall()
    except Exception as exc:  # noqa: BLE001
        print(f"(no se pudo leer el conteo de la base de datos: {exc})")
        return 0
    if not filas:
        print("(sin datos para comparar)")
        return 0
    print("Productos con precio de hoy por tienda (vs. promedio de los días anteriores):")
    for tienda, hoy, prom in filas:
        prom = float(prom)
        marca = ""
        if prom > 0 and hoy < prom * 0.9:
            marca = f"   <-- CAYÓ {100 - 100 * hoy / prom:.0f} %"
        print(f"  - {tienda}: {hoy} (antes ~{prom:.0f}){marca}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
