"""Carga real de ubicaciones de tiendas físicas desde OpenStreetMap.

Consulta Overpass API (datos abiertos de OpenStreetMap, sin necesidad de
cuenta ni llave de API) por sucursales de supermercado dentro de una
ciudad, y las homologa contra la tabla `supermarkets` -- nunca contra una
lista fija de nombres: si se agrega un sexto supermercado a esa tabla, la
siguiente ejecución de este script lo incluye sin ningún cambio de código.

Ejecutar (con el venv del scraper, que ya tiene `requests`):
    scraper/.venv/Scripts/python.exe -m etl.load_physical_stores
    scraper/.venv/Scripts/python.exe -m etl.load_physical_stores --city "Bogotá, Colombia"
    scraper/.venv/Scripts/python.exe -m etl.load_physical_stores --bbox 6.95,-73.25,7.25,-73.0

Sin argumentos consulta toda el área metropolitana de Bucaramanga
(Bucaramanga, Floridablanca, Girón y Piedecuesta). Incluye sucursales
dibujadas en OpenStreetMap como punto O como edificio (los supermercados
grandes suelen ser edificios).

No inventa ninguna tienda: si Overpass no devuelve nada para un
supermercado en la ciudad consultada, simplemente no se agrega ninguna
fila para él -- la tabla queda vacía para ese caso, honestamente, en vez
de rellenarse con datos aproximados.
"""
from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

import requests

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from etl import db  # noqa: E402
from shared.category_filter import normalizar_texto  # noqa: E402

logger = logging.getLogger("etl.physical_stores")

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
NOMINATIM_REVERSE_URL = "https://nominatim.openstreetmap.org/reverse"
OVERPASS_URLS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
)
# Cuadro (sur, oeste, norte, este) del área metropolitana de Bucaramanga.
DEFAULT_BBOX = (6.95, -73.25, 7.25, -73.0)
DEFAULT_CITY = None

# Nominatim y Overpass son servicios públicos gratuitos de OpenStreetMap,
# no una API con llave -- su política de uso pide identificar el cliente
# con un User-Agent real, no simular un navegador.
HEADERS = {"User-Agent": "Convenia/1.0 (proyecto academico UPB; contacto: u22212045@utp.edu.pe)"}


def _get_active_supermarkets(conn) -> list[dict]:
    with conn.cursor() as cur:
        cur.execute("SELECT id, name FROM supermarkets WHERE is_active = TRUE")
        return [{"id": row[0], "name": row[1]} for row in cur.fetchall()]


def _geocode_city(city: str) -> tuple[float, float, float, float]:
    """Devuelve el cuadro (sur, oeste, norte, este) de la ciudad, vía Nominatim."""
    resp = requests.get(
        NOMINATIM_URL,
        params={"q": city, "format": "json", "limit": 1},
        headers=HEADERS,
        timeout=15,
    )
    resp.raise_for_status()
    results = resp.json()
    if not results:
        raise ValueError(f"No se pudo geocodificar la ciudad: {city!r}")

    # Nominatim devuelve [sur, norte, oeste, este] como strings.
    south, north, west, east = (float(v) for v in results[0]["boundingbox"])
    return south, west, north, east


def _query_overpass(bbox: tuple[float, float, float, float], names: list[str]) -> list[dict]:
    south, west, north, east = bbox
    # Alternancia de nombres en una sola expresión regular: la lista de
    # supermercados a buscar sale de la base de datos (parámetro `names`),
    # nunca queda escrita a mano en esta consulta.
    # OpenStreetMap distingue tildes al buscar: se prueba cada nombre con y
    # sin ellas ("Éxito"/"Exito", "Olímpica"/"Olimpica").
    variantes = {n for name in names for n in (name, normalizar_texto(name))}
    pattern = "|".join(sorted(variantes))
    query = f"""
    [out:json][timeout:60];
    (
      nwr["shop"~"supermarket|convenience|department_store|hypermarket"]["name"~"{pattern}",i]({south},{west},{north},{east});
    );
    out center tags;
    """
    # Los servidores públicos de Overpass se saturan (504): se reintenta y
    # se rota entre espejos antes de rendirse.
    ultimo_error: Exception | None = None
    for intento in range(6):
        url = OVERPASS_URLS[intento % len(OVERPASS_URLS)]
        try:
            resp = requests.post(url, data={"data": query}, headers=HEADERS, timeout=120)
            resp.raise_for_status()
            return resp.json().get("elements", [])
        except requests.RequestException as exc:
            ultimo_error = exc
            logger.warning("Overpass %s falló (%s); reintentando...", url, exc)
            time.sleep(5 * (intento + 1))
    raise RuntimeError(f"Overpass no respondió tras varios intentos: {ultimo_error}")


def _coords(element: dict) -> tuple[float | None, float | None]:
    """Lat/lon de un punto, o el centro de un edificio/relación."""
    if "lat" in element:
        return element["lat"], element["lon"]
    center = element.get("center") or {}
    return center.get("lat"), center.get("lon")


def _reverse_address(lat: float, lon: float) -> str | None:
    """Calle y barrio por Nominatim, para tiendas que OSM no trae con
    dirección. Nominatim pide máximo 1 consulta por segundo."""
    time.sleep(1.1)
    try:
        resp = requests.get(
            NOMINATIM_REVERSE_URL,
            params={"lat": lat, "lon": lon, "format": "jsonv2", "zoom": 18},
            headers=HEADERS,
            timeout=15,
        )
        resp.raise_for_status()
        addr = resp.json().get("address", {})
    except Exception as exc:  # sin dirección es mejor que sin tienda
        logger.warning("Sin dirección para (%s, %s): %s", lat, lon, exc)
        return None
    partes = [addr.get("road"), addr.get("suburb") or addr.get("neighbourhood")]
    partes = [p for p in partes if p]
    return " · ".join(partes) if partes else None


def _match_supermarket(osm_name: str, supermarkets: list[dict]) -> dict | None:
    """A cuál supermercado de nuestra tabla corresponde este nombre de OSM.

    Coincidencia por contención de texto normalizado (sin tildes ni
    mayúsculas), no exacta: OSM puede tener "Éxito Express" o
    "Supermercado Éxito" para lo que en `supermarkets.name` es sólo "Éxito".
    """
    osm_norm = normalizar_texto(osm_name)
    for supermarket in supermarkets:
        if normalizar_texto(supermarket["name"]) in osm_norm:
            return supermarket
    return None


def _build_address(tags: dict) -> str | None:
    calle = " ".join(p for p in (tags.get("addr:street"), tags.get("addr:housenumber")) if p)
    barrio = tags.get("addr:suburb")
    partes = [p for p in (calle, barrio) if p]
    return " · ".join(partes) if partes else None


def _upsert_store(conn, supermarket_id: int, node: dict) -> bool:
    tags = node.get("tags", {})
    lat, lon = _coords(node)
    if lat is None or lon is None:
        return False
    address = _build_address(tags) or _reverse_address(lat, lon)
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO physical_stores
                (supermarket_id, external_id, name, address, city, latitude, longitude)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (supermarket_id, external_id) DO UPDATE SET
                name = EXCLUDED.name,
                address = EXCLUDED.address,
                city = EXCLUDED.city,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                is_active = TRUE
            RETURNING (xmax = 0) AS inserted
            """,
            (
                supermarket_id,
                # Los puntos conservan el formato histórico "osm:<id>" para no
                # duplicar tiendas ya cargadas; edificios/relaciones llevan el tipo.
                f"osm:{node['id']}" if node["type"] == "node" else f"osm:{node['type']}/{node['id']}",
                tags.get("name", "").strip(),
                address,
                tags.get("addr:city"),
                lat,
                lon,
            ),
        )
        (inserted,) = cur.fetchone()
    return inserted


def run(city: str | None = DEFAULT_CITY, bbox: tuple[float, float, float, float] = DEFAULT_BBOX) -> None:
    with db.get_connection() as conn:
        supermarkets = _get_active_supermarkets(conn)
        if not supermarkets:
            logger.warning("No hay supermercados activos en la tabla `supermarkets`; nada que buscar.")
            return

        if city:
            logger.info("Geocodificando %r ...", city)
            bbox = _geocode_city(city)

        nombres = [s["name"] for s in supermarkets]
        logger.info("Consultando Overpass por: %s", ", ".join(nombres))
        nodos = _query_overpass(bbox, nombres)
        logger.info("Overpass devolvió %d nodos candidatos.", len(nodos))

        nuevas, actualizadas, sin_match = 0, 0, 0
        for node in nodos:
            osm_name = node.get("tags", {}).get("name")
            if not osm_name:
                continue

            supermarket = _match_supermarket(osm_name, supermarkets)
            if supermarket is None:
                sin_match += 1
                continue

            insertado = _upsert_store(conn, supermarket["id"], node)
            if insertado:
                nuevas += 1
            else:
                actualizadas += 1

        conn.commit()
        logger.info(
            "Listo: %d tiendas nuevas, %d actualizadas, %d nodos sin corresponder a ningún supermercado activo.",
            nuevas,
            actualizadas,
            sin_match,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Carga ubicaciones reales de tiendas desde OpenStreetMap")
    parser.add_argument("--city", default=DEFAULT_CITY, help="Ciudad a geocodificar (por defecto: área metropolitana de Bucaramanga)")
    parser.add_argument("--bbox", help="Cuadro sur,oeste,norte,este (alternativa a --city)")
    args = parser.parse_args()
    bbox = tuple(float(v) for v in args.bbox.split(",")) if args.bbox else DEFAULT_BBOX

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    run(city=args.city, bbox=bbox)


if __name__ == "__main__":
    main()
