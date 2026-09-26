"""Alcance por supermercados: el subconjunto de supermercados que tienen al
menos una tienda dentro del rango de la persona.

La app calcula ese subconjunto (`GET /stores/coverage`) y lo envía como
`?supermarkets=D1,EXITO` a los endpoints que muestran precios. Sin el
parámetro (`None`) no se filtra nada; con el parámetro vacío (`[]`) ningún
supermercado está al alcance y no se devuelve ninguna oferta.
"""
from __future__ import annotations

from fastapi import Query


def parse_supermarket_scope(
    supermarkets: str | None = Query(
        None,
        description="Códigos de supermercado separados por coma a los que limitar los precios "
        "(vacío = ninguno al alcance; ausente = sin filtro)",
    ),
) -> list[str] | None:
    if supermarkets is None:
        return None
    return [code.strip().upper() for code in supermarkets.split(",") if code.strip()]


def sql_scope_clause(alias: str, codes: list[str] | None) -> str:
    """Fragmento SQL que exige que el source_product `alias` sea de un
    supermercado del alcance; vacío si no hay filtro."""
    if codes is None:
        return ""
    return (
        f"AND EXISTS (SELECT 1 FROM supermarkets scope_s "
        f"WHERE scope_s.id = {alias}.supermarket_id AND scope_s.code = ANY(:sm_codes))"
    )
