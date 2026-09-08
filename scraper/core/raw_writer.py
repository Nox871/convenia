"""RAW histórico inmutable, compartido por los 5 conectores.

Antes, cada conector escribía siempre el mismo archivo fijo
(`<code>_raw.json`), así que cada corrida sobrescribía la anterior y no
quedaba ningún historial: el RAW de una ejecución completada no debe
modificarse ni perderse por una ejecución posterior.

Este módulo escribe SIEMPRE un archivo nuevo con timestamp en el nombre, y
mantiene un pequeño archivo puntero (`latest.json`) para que el ETL sepa
cuál es "el más reciente" sin tener que listar el directorio y parsear
nombres.

Nota de entorno: se usa un archivo puntero JSON en vez de un symlink porque
el entorno de referencia es Windows, donde crear symlinks requiere
privilegios elevados; un archivo puntero es portable y no necesita permisos
especiales.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

LATEST_POINTER_NAME = "latest.json"


def construir_nombre_raw(code: str, timestamp: datetime | None = None) -> str:
    ts = (timestamp or datetime.now(timezone.utc)).strftime("%Y%m%dT%H%M%SZ")
    return f"{code.lower()}_raw_{ts}.json"


def guardar_raw_snapshot(base_dir: Path, code: str, payload: dict) -> Path:
    """Escribe un archivo RAW nuevo (nunca sobrescribe uno existente) dentro de
    `base_dir` y actualiza el puntero `latest.json` para que apunte a él.

    Devuelve la ruta del archivo escrito.
    """
    base_dir = Path(base_dir)
    base_dir.mkdir(parents=True, exist_ok=True)

    ruta = base_dir / construir_nombre_raw(code)
    with open(ruta, "w", encoding="utf-8") as archivo:
        json.dump(payload, archivo, ensure_ascii=False, indent=2)

    puntero = base_dir / LATEST_POINTER_NAME
    with open(puntero, "w", encoding="utf-8") as archivo:
        json.dump({"file": ruta.name}, archivo)

    return ruta


def resolver_ultimo_raw(base_dir: Path, code: str | None = None) -> Path:
    """Resuelve cuál es el RAW más reciente de `base_dir`.

    Orden de resolución:
    1. Puntero `latest.json`, si existe y el archivo que referencia sigue ahí.
    2. El archivo `<code>_raw_*.json` con mtime más reciente (por si el
       puntero no existe todavía, ej. primera corrida tras este cambio).
    3. El archivo legacy `<code>_raw.json` (nombre fijo, previo a este cambio).
    """
    base_dir = Path(base_dir)

    puntero = base_dir / LATEST_POINTER_NAME
    if puntero.exists():
        try:
            nombre = json.loads(puntero.read_text(encoding="utf-8"))["file"]
        except (json.JSONDecodeError, KeyError):
            nombre = None
        if nombre:
            candidato = base_dir / nombre
            if candidato.exists():
                return candidato

    patron = f"{code.lower()}_raw_*.json" if code else "*_raw_*.json"
    candidatos = sorted(base_dir.glob(patron), key=lambda p: p.stat().st_mtime)
    if candidatos:
        return candidatos[-1]

    if code:
        legacy = base_dir / f"{code.lower()}_raw.json"
        if legacy.exists():
            return legacy

    raise FileNotFoundError(f"No hay ningún RAW disponible en {base_dir}")
