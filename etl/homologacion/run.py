"""Homologación: agrupa `source_products` de CUALQUIER supermercado en
`products` canónicos + `product_matches`, cuando hay evidencia real de que
son el mismo producto.

Ejecutar (desde la raíz del proyecto, con el venv del scraper que ya tiene
psycopg2/dotenv):

    python -m etl.homologacion.run

Diseño (N supermercados, no solo D1/Éxito):
    - Solo evalúa `source_products` SIN match previo (`NOT EXISTS` contra
      `product_matches`), así que reprocesar no duplica nada: cada
      source_product termina con a lo sumo UNA fila en product_matches
      (columna UNIQUE), y cada par ya emparejado no se vuelve a comparar.
    - Dentro de cada bucket de categoría, se comparan TODOS los pares de
      productos de supermercados DISTINTOS (nunca dos productos del mismo
      supermercado entre sí). Los pares con score suficiente (CONFIRMED o
      REVIEW) se agrupan primero con un union-find para acotar el problema,
      pero ese grupo NO se persiste tal cual: la relación "~" no es
      transitiva (A~B y B~C no implica A~C -- p.ej. dos presentaciones
      distintas de arroz que "puentean" por un tercer producto), así que
      `_descomponer_en_subgrupos` parte cada componente en subgrupos de
      ENLACE COMPLETO: todos los pares comparados directamente sobre el
      umbral, sin dos miembros del mismo supermercado y con cantidad
      equivalente. Un miembro que no encaja en
      ningún subgrupo de 2+ queda suelto (lo puede recoger otra corrida).
      Verificable con `python -m etl.homologacion.verificar_grupos`.
    - Solo crea un `products` canónico cuando el grupo resultante tiene 2 o
      más `source_products` (evidencia real de coincidencia entre
      supermercados). No copia cada source_product a products "por si
      acaso" -- ver README de esta carpeta.
    - No genera filas REJECTED masivamente (ver matcher.py): ese status
      queda para cuando una fila REVIEW se descarta explícitamente más
      adelante (paso manual o una futura re-ejecución con mejor señal).

Cross-run: antes de agrupar por union-find "no resueltos" contra
"no resueltos", cada candidato se intenta enlazar primero contra los
`products` canónicos YA EXISTENTES del mismo bucket, reutilizando el mismo
`comparar()` de matcher.py. El enlace sólo se hace si el candidato es
`_par_directo_valido` contra TODOS los `source_products` que ya cuelgan de
ese canónico (misma regla de enlace completo que el paso intra-run) y
ninguno es de su mismo supermercado -- así el enlace cross-run tampoco
puede fusionar presentaciones distintas ni dos productos de una misma
cadena vía un canónico puente. Nunca crea un canónico duplicado. Sólo lo
que no enlaza a ningún canónico existente pasa al union-find intra-run.
"""
from __future__ import annotations

import logging
import sys
from collections import defaultdict
from pathlib import Path

from etl import db
from etl.homologacion.matcher import (
    ProductoNormalizado,
    comparar,
    construir_normalizado,
)

_PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

# Se agrupa por la ETIQUETA AMIGABLE (nombre del producto, con el pasillo como
# respaldo) y no por el pasillo crudo: dos supermercados archivan el mismo
# tipo de producto bajo pasillos distintos (ej. huevos bajo "Lácteos" en uno y
# bajo "Huevos" en otro), y agrupar por pasillo los mandaba a "buckets"
# distintos que nunca se comparaban entre sí -- perdiendo homologaciones
# válidas en silencio. `categoria_de_producto` es la misma regla que ya usa
# el backend para mostrarle la categoría al consumidor.
from shared.category_producto import categoria_de_producto  # noqa: E402

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
            ORDER BY sp.id
            """
        )
        return cur.fetchall()


def _cargar_productos_canonicos(conn):
    """`products` ya existentes (de corridas anteriores), con lo necesario
    para reconstruir un `ProductoNormalizado` "ancla" y compararlos con el
    mismo `comparar()` que ya existe."""
    with conn.cursor() as cur:
        cur.execute("SELECT id, name, brand, category FROM products")
        return cur.fetchall()


def _normalizado_desde_canonico(product_id: int, name: str, brand: str | None,
                                 category: str | None) -> ProductoNormalizado | None:
    bucket = categoria_de_producto(name, category)
    if bucket is None:
        return None
    # source_product_id negativo (sentinel): nunca choca con un id real de
    # source_products (siempre positivo), y permite "deshacerlo" con -id
    # para recuperar el products.id original tras el match.
    return construir_normalizado(
        source_product_id=-product_id,
        supermarket_code="CANONICAL",
        name_raw=name,
        brand_raw=brand,
        bucket_categoria=bucket,
    )


def _cantidad_equivalente(a: ProductoNormalizado, b: ProductoNormalizado) -> bool:
    """True salvo que ambos tengan cantidad y NO sea la misma (dimensión y
    valor). Si a alguno le falta la cantidad, no se puede afirmar que sean
    distintos -> no bloquea aquí (lo filtra el score del nombre/marca)."""
    if a.cantidad and b.cantidad:
        return a.cantidad.compatible_con(b.cantidad) and a.cantidad.es_igual_a(b.cantidad)
    return True


def _par_directo_valido(a: ProductoNormalizado, b: ProductoNormalizado) -> bool:
    """¿`a` y `b` pueden compartir `products.id`? Supermercados distintos,
    comparación directa por encima del umbral y cantidad equivalente. Se usa
    en el enlace cross-run, donde no hay un `resultado_par` precomputado."""
    if a.supermarket_code == b.supermarket_code:
        return False
    if not _cantidad_equivalente(a, b):
        return False
    return comparar(a, b).status is not None


def _miembros_de_canonico(conn, product_id: int, bucket: str,
                          cache: dict) -> list[ProductoNormalizado]:
    """`source_products` YA enlazados a `product_id`, como
    `ProductoNormalizado`, para validar contra ellos un candidato nuevo del
    mismo bucket (mismo criterio que el union-find intra-run)."""
    if product_id in cache:
        return cache[product_id]
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT sp.id, s.code, sp.name_raw, sp.brand_raw
            FROM product_matches pm
            JOIN source_products sp ON sp.id = pm.source_product_id
            JOIN supermarkets s ON s.id = sp.supermarket_id
            WHERE pm.product_id = %s
            """,
            (product_id,),
        )
        miembros = [
            construir_normalizado(sp_id, code, name_raw, brand_raw, bucket)
            for sp_id, code, name_raw, brand_raw in cur.fetchall()
        ]
    cache[product_id] = miembros
    return miembros


def _intentar_enlazar_canonicos(conn, candidatos: list[ProductoNormalizado],
                                 canonicos: list[ProductoNormalizado], stats: dict) -> set[int]:
    """Para cada `candidato` sin match, intenta enlazarlo a un `products`
    canónico existente del mismo bucket. Ordena los canónicos por score y
    toma el primero cuyos MIEMBROS reales cumplan, todos, la misma regla que
    el union-find intra-run: ningún miembro del mismo supermercado que el
    candidato y todos `_par_directo_valido` con él (comparación directa +
    cantidad equivalente). Así el enlace cross-run tampoco puede fusionar
    presentaciones distintas ni dos productos del mismo supermercado vía un
    canónico puente. Inserta apuntando al products.id EXISTENTE (nunca crea
    uno) y devuelve los source_product_id ya resueltos."""
    resueltos: set[int] = set()
    if not canonicos:
        return resueltos

    miembros_cache: dict[int, list[ProductoNormalizado]] = {}

    for candidato in candidatos:
        ranked = sorted(
            ((comparar(candidato, canon), canon) for canon in canonicos),
            key=lambda t: t[0].score,
            reverse=True,
        )

        for resultado, canonico in ranked:
            if resultado.status is None:
                break  # ninguno posterior tiene mejor score

            product_id = -canonico.source_product_id  # deshacer el sentinel
            miembros = _miembros_de_canonico(
                conn, product_id, candidato.bucket_categoria, miembros_cache
            )
            if any(m.supermarket_code == candidato.supermarket_code for m in miembros):
                continue
            if not all(_par_directo_valido(candidato, m) for m in miembros):
                continue

            with conn:
                _insertar_match(
                    conn, candidato.source_product_id, product_id,
                    _match_method(resultado), resultado.score, resultado.status,
                )

            miembros.append(candidato)  # visible para los siguientes candidatos
            resueltos.add(candidato.source_product_id)
            stats["enlazados_a_canonico_existente"] += 1
            logger.info(
                "%s [%s (%s)] enlazado a products.id=%s existente (score=%.2f, %s)",
                candidato.bucket_categoria, candidato.name_raw, candidato.supermarket_code,
                product_id, resultado.score, resultado.motivo,
            )
            break

    return resueltos


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


# ---------------------------------------------------------------------- #
# Union-Find (Disjoint Set) para agrupar cadenas de coincidencias
# ---------------------------------------------------------------------- #
class UnionFind:
    def __init__(self, elementos):
        self._padre = {e: e for e in elementos}

    def encontrar(self, x):
        raiz = x
        while self._padre[raiz] != raiz:
            raiz = self._padre[raiz]
        while self._padre[x] != raiz:
            self._padre[x], x = raiz, self._padre[x]
        return raiz

    def unir(self, a, b):
        raiz_a, raiz_b = self.encontrar(a), self.encontrar(b)
        if raiz_a != raiz_b:
            self._padre[raiz_b] = raiz_a

    def grupos(self):
        agrupados = defaultdict(list)
        for elemento in self._padre:
            agrupados[self.encontrar(elemento)].append(elemento)
        return list(agrupados.values())


def _co_agrupables(a: ProductoNormalizado, b: ProductoNormalizado,
                   resultado_par: dict) -> bool:
    """Dos source_products pueden compartir `products.id` sólo si: son de
    supermercados distintos, se compararon DIRECTAMENTE por encima del
    umbral (hay una arista en `resultado_par`, no un enlace transitivo), y
    -- cuando ambos tienen cantidad -- esa cantidad es de la misma dimensión
    y equivalente. Esto evita que "A~B y B~C" fusione A con C cuando A y C
    son incompatibles."""
    if a.supermarket_code == b.supermarket_code:
        return False
    if frozenset((a.source_product_id, b.source_product_id)) not in resultado_par:
        return False
    return _cantidad_equivalente(a, b)


def _descomponer_en_subgrupos(
    miembros: list[ProductoNormalizado], resultado_par: dict
) -> list[list[ProductoNormalizado]]:
    """Parte un grupo de union-find (relación "~" transitiva) en subgrupos
    de enlace COMPLETO: dentro de cada subgrupo todos los pares se
    compararon directamente por encima del umbral, no hay dos miembros del
    mismo supermercado y todas las cantidades son equivalentes.

    Clustering voraz: se siembra desde la arista de mayor score y se agrega
    un miembro nuevo sólo si es `_co_agrupables` con TODOS los ya incluidos.
    Un miembro que no encaja en ningún subgrupo de 2+ queda suelto (no se
    homologa)."""
    por_id = {m.source_product_id: m for m in miembros}
    ids = sorted(por_id)

    aristas: list[tuple[float, int, int]] = []
    for i, x in enumerate(ids):
        for y in ids[i + 1:]:
            if _co_agrupables(por_id[x], por_id[y], resultado_par):
                score = resultado_par[frozenset((x, y))].score
                aristas.append((score, x, y))
    aristas.sort(key=lambda t: (-t[0], t[1], t[2]))

    asignado: set[int] = set()
    subgrupos: list[list[ProductoNormalizado]] = []

    for _score, x, y in aristas:
        if x in asignado or y in asignado:
            continue
        grupo_ids = [x, y]
        supers = {por_id[x].supermarket_code, por_id[y].supermarket_code}
        crecio = True
        while crecio:
            crecio = False
            for c in ids:
                if c in asignado or c in grupo_ids or por_id[c].supermarket_code in supers:
                    continue
                if all(_co_agrupables(por_id[c], por_id[m], resultado_par) for m in grupo_ids):
                    grupo_ids.append(c)
                    supers.add(por_id[c].supermarket_code)
                    crecio = True
        asignado.update(grupo_ids)
        subgrupos.append([por_id[i] for i in grupo_ids])

    return subgrupos


def _procesar_bucket(conn, bucket: str, productos: list[ProductoNormalizado],
                      categoria_por_id: dict, stats: dict) -> None:
    por_id = {p.source_product_id: p for p in productos}
    uf = UnionFind(por_id.keys())

    # resultado_par[frozenset(id_a, id_b)] = ResultadoComparacion de cada
    # par de supermercados DISTINTOS que superó el umbral. Es la evidencia
    # de aristas directas que usa `_descomponer_en_subgrupos` para no
    # confiar en la transitividad del union-find.
    resultado_par: dict = {}

    for i, a in enumerate(productos):
        for b in productos[i + 1:]:
            if a.supermarket_code == b.supermarket_code:
                continue  # nunca homologar dos productos del mismo supermercado

            resultado = comparar(a, b)
            if resultado.status is None:
                continue

            uf.unir(a.source_product_id, b.source_product_id)
            resultado_par[frozenset((a.source_product_id, b.source_product_id))] = resultado

            logger.info(
                "%s [%s (%s)] <-> [%s (%s)] -> %s (score=%.2f, %s)",
                bucket, a.name_raw, a.supermarket_code,
                b.name_raw, b.supermarket_code,
                resultado.status, resultado.score, resultado.motivo,
            )

    for grupo in uf.grupos():
        if len(grupo) < 2:
            stats["sin_candidato"] += 1
            continue

        miembros_grupo = [por_id[sp_id] for sp_id in grupo]
        subgrupos = _descomponer_en_subgrupos(miembros_grupo, resultado_par)
        homologados = 0

        for subgrupo in subgrupos:
            if len(subgrupo) < 2:
                continue

            # Para cada miembro, el mejor enlace directo DENTRO del subgrupo
            # (todo par del subgrupo es `_co_agrupables` -> tiene entrada).
            mejor_por_miembro = {
                m.source_product_id: max(
                    (
                        resultado_par[frozenset((m.source_product_id, o.source_product_id))]
                        for o in subgrupo
                        if o.source_product_id != m.source_product_id
                    ),
                    key=lambda r: r.score,
                )
                for m in subgrupo
            }

            # Ancla determinista: el de menor (supermercado, id) del subgrupo,
            # sólo para tener un nombre/marca/cantidad real y estable en
            # `products` -- no se fabrica ningún dato.
            ancla = min(subgrupo, key=lambda p: (p.supermarket_code, p.source_product_id))
            categoria_texto = categoria_por_id.get(ancla.source_product_id)

            with conn:
                product_id = _crear_producto(conn, ancla, categoria_texto)
                for miembro in subgrupo:
                    r = mejor_por_miembro[miembro.source_product_id]
                    _insertar_match(
                        conn, miembro.source_product_id, product_id,
                        _match_method(r), r.score, r.status,
                    )

            homologados += len(subgrupo)
            stats["products_creados"] += 1
            stats["source_products_homologados"] += len(subgrupo)
            if any(r.status == "CONFIRMED" for r in mejor_por_miembro.values()):
                stats["matches_confirmed"] += 1
            else:
                stats["matches_review"] += 1

        stats["sin_candidato"] += len(grupo) - homologados


_PRIORIDAD_ANCLA = {"EXITO": 0, "CARULLA": 1, "JUMBO": 2, "OLIMPICA": 3, "D1": 4}


def _homologar_por_ean(conn, stats: dict) -> None:
    """Paso 0: une por CÓDIGO DE BARRAS productos de tiendas distintas.

    Mismo EAN = mismo artículo del fabricante, sin depender de cómo cada tienda
    escribe el nombre (orden de palabras, abreviaturas, "malla multiusos" contra
    "esponja doble uso"). Sólo toca productos activos SIN match previo, y respeta
    las mismas reglas del resto de la homologación: a lo sumo un producto activo
    por supermercado en cada canónico, y si el nombre trae una cantidad
    distinta (un catálogo que reutiliza el EAN para otra presentación) el enlace
    queda en REVIEW y no se muestra como comparable.

    Lo que no se une aquí sigue al comparador por nombre, como antes."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT sp.id, s.code, sp.name_raw, sp.brand_raw, sp.ean, sc.name_raw,
                   pm.product_id, pm.status
            FROM source_products sp
            JOIN supermarkets s ON s.id = sp.supermarket_id
            LEFT JOIN source_categories sc ON sc.id = sp.source_category_id
            LEFT JOIN product_matches pm ON pm.source_product_id = sp.id
            WHERE sp.is_active = TRUE AND sp.ean IS NOT NULL
            """
        )
        filas = cur.fetchall()

    por_ean = defaultdict(list)
    for sp_id, code, name_raw, brand_raw, ean, categoria, product_id, status in filas:
        por_ean[ean].append((sp_id, code, name_raw, brand_raw, categoria, product_id, status))

    for ean, miembros in por_ean.items():
        if len({m[1] for m in miembros}) < 2:
            continue
        sin_match = [m for m in miembros if m[5] is None]
        if not sin_match:
            continue

        def normalizado(m):
            bucket = categoria_de_producto(m[2], m[4])
            if bucket is None:
                return None  # fuera de canasta
            return construir_normalizado(m[0], m[1], m[2], m[3], bucket)

        confirmados = [m for m in miembros if m[5] is not None and m[6] == "CONFIRMED"]
        orden = lambda m: (_PRIORIDAD_ANCLA.get(m[1], 9), m[0])  # noqa: E731

        if confirmados:
            # Ya hay un canónico para este código: se suman los que faltan.
            target = min({m[5] for m in confirmados})
            ref_m = min((m for m in confirmados if m[5] == target), key=orden)
            referencia = normalizado(ref_m)
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT s.code FROM product_matches pm
                    JOIN source_products sp ON sp.id = pm.source_product_id AND sp.status = 'ACTIVE'
                    JOIN supermarkets s ON s.id = sp.supermarket_id
                    WHERE pm.product_id = %s AND pm.status = 'CONFIRMED'
                    """,
                    (target,),
                )
                ocupadas = {r[0] for r in cur.fetchall()}
            candidatos = sorted(sin_match, key=orden)
            creado = False
        else:
            # Ninguno tiene canónico: se crea uno si al menos dos tiendas coinciden.
            candidatos = sorted(sin_match, key=orden)
            ancla_m = None
            for m in candidatos:
                if normalizado(m) is not None:
                    ancla_m = m
                    break
            if ancla_m is None:
                continue
            referencia = normalizado(ancla_m)
            equivalentes = {
                m[1] for m in candidatos
                if (n := normalizado(m)) is not None and _cantidad_equivalente(referencia, n)
            }
            if len(equivalentes) < 2:
                continue
            with conn:
                target = _crear_producto(conn, referencia, ancla_m[4])
                with conn.cursor() as cur:
                    cur.execute("UPDATE products SET barcode = %s WHERE id = %s", (ean, target))
            stats["products_creados"] += 1
            stats["products_creados_por_ean"] += 1
            ocupadas = set()
            creado = True

        vistos = set(ocupadas)
        for m in candidatos:
            if m[1] in vistos:
                continue
            n = normalizado(m)
            if n is None:
                continue
            equivalente = referencia is None or _cantidad_equivalente(referencia, n)
            status = "CONFIRMED" if equivalente else "REVIEW"
            metodo = "ean" if equivalente else "ean+cantidad_distinta"
            with conn:
                _insertar_match(conn, m[0], target, metodo, 1.0 if equivalente else 0.6, status)
            if status == "CONFIRMED":
                vistos.add(m[1])
                stats["matches_por_ean"] += 1
            stats["source_products_homologados"] += 1


def _refrescar_nombres_canonicos(conn) -> int:
    """Si el nombre de un producto canónico ya no coincide con ninguno de sus
    productos activos, lo reemplaza por el de uno de ellos.

    El canónico toma su nombre del primer producto que lo creó; si ese producto
    cambia de id o sale del catálogo, el grupo se quedaba con un nombre que ya
    no describe lo que agrupa (un "doble uso anatómica" mostrando precios de una
    "malla multiusos"). Se prefiere el nombre de Éxito o Carulla, que escriben
    marca y presentación de forma más limpia."""
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE products p SET name = x.name_raw, updated_at = now()
            FROM (
                SELECT DISTINCT ON (pm.product_id) pm.product_id, sp.name_raw
                FROM product_matches pm
                JOIN source_products sp ON sp.id = pm.source_product_id AND sp.status = 'ACTIVE'
                JOIN supermarkets s ON s.id = sp.supermarket_id
                WHERE pm.status = 'CONFIRMED'
                ORDER BY pm.product_id,
                         CASE s.code WHEN 'EXITO' THEN 0 WHEN 'CARULLA' THEN 1
                                     WHEN 'JUMBO' THEN 2 WHEN 'OLIMPICA' THEN 3 ELSE 4 END,
                         sp.id
            ) x
            WHERE p.id = x.product_id
              AND NOT EXISTS (
                  SELECT 1 FROM product_matches pm2
                  JOIN source_products sp2 ON sp2.id = pm2.source_product_id AND sp2.status = 'ACTIVE'
                  WHERE pm2.product_id = p.id AND pm2.status = 'CONFIRMED'
                    AND lower(sp2.name_raw) = lower(p.name)
              )
            RETURNING p.id
            """
        )
        return len(cur.fetchall())


def ejecutar() -> dict:
    stats = {
        "candidatos_por_supermercado": defaultdict(int),
        "sin_bucket": 0,
        "products_creados": 0,
        "source_products_homologados": 0,
        "matches_confirmed": 0,
        "matches_review": 0,
        "sin_candidato": 0,
        "enlazados_a_canonico_existente": 0,
        "nombres_actualizados": 0,
        "matches_por_ean": 0,
        "products_creados_por_ean": 0,
    }

    with db.get_connection() as conn:
        stats["nombres_actualizados"] = _refrescar_nombres_canonicos(conn)
        _homologar_por_ean(conn, stats)
        filas = _cargar_no_resueltos(conn)

        canonicos_por_bucket = defaultdict(list)
        for product_id, name, brand, category in _cargar_productos_canonicos(conn):
            normalizado = _normalizado_desde_canonico(product_id, name, brand, category)
            if normalizado:
                canonicos_por_bucket[normalizado.bucket_categoria].append(normalizado)

        por_bucket = defaultdict(list)
        categoria_por_id = {}

        for row in filas:
            sp_id, code, name_raw, brand_raw, category_name = row
            categoria_por_id[sp_id] = category_name

            bucket = categoria_de_producto(name_raw, category_name)
            if bucket is None:
                stats["sin_bucket"] += 1
                continue

            normalizado = construir_normalizado(sp_id, code, name_raw, brand_raw, bucket)
            por_bucket[bucket].append(normalizado)
            stats["candidatos_por_supermercado"][code] += 1

        for bucket, productos in por_bucket.items():
            # Paso 1 (cross-run): intentar enlazar cada candidato contra un
            # products.id YA EXISTENTE de este bucket antes de comparar entre
            # sí -- evita crear un canónico duplicado.
            canonicos_bucket = canonicos_por_bucket.get(bucket, [])
            if canonicos_bucket:
                resueltos = _intentar_enlazar_canonicos(conn, productos, canonicos_bucket, stats)
                productos = [p for p in productos if p.source_product_id not in resueltos]

            # Paso 2 (intra-run, como antes): lo que no enlazó a ningún
            # canónico existente se compara entre sí vía union-find.
            if len({p.supermarket_code for p in productos}) < 2:
                stats["sin_candidato"] += len(productos)
                continue
            _procesar_bucket(conn, bucket, productos, categoria_por_id, stats)

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
    print("Candidatos sin match previo, por supermercado:")
    for code, n in sorted(stats["candidatos_por_supermercado"].items()):
        print(f"  {code:10s} {n}")
    print(f"Descartados sin bucket de categoría:   {stats['sin_bucket']}")
    print(f"Enlazados a canónico existente:        {stats['enlazados_a_canonico_existente']}")
    print(f"Nombres de canónicos actualizados:     {stats['nombres_actualizados']}")
    print(f"Unidos por código de barras (EAN):     {stats['matches_por_ean']} "
          f"({stats['products_creados_por_ean']} canónicos nuevos)")
    print(f"Productos canónicos creados:           {stats['products_creados']}")
    print(f"  - source_products homologados:       {stats['source_products_homologados']}")
    print(f"  - grupos con al menos un CONFIRMED:   {stats['matches_confirmed']}")
    print(f"  - grupos solo REVIEW:                 {stats['matches_review']}")
    print(f"Sin candidato suficientemente bueno:    {stats['sin_candidato']}")
    print("-" * 40)
    print("FINALIZADO")


if __name__ == "__main__":
    main()
