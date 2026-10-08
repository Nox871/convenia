"""Búsquedas frecuentes (tabla `search_terms`)."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.engine import Connection


def record(conn: Connection, key: str, display: str) -> None:
    """Cuenta una búsqueda. Si ya había una con tildes, se conserva esa forma."""
    conn.execute(
        text(
            """
            INSERT INTO search_terms (term, display, searches, last_searched_at)
            VALUES (:term, :display, 1, now())
            ON CONFLICT (term) DO UPDATE SET
                searches = search_terms.searches + 1,
                last_searched_at = now(),
                display = CASE WHEN unaccent(EXCLUDED.display) <> EXCLUDED.display
                               THEN EXCLUDED.display ELSE search_terms.display END
            """
        ),
        {"term": key, "display": display},
    )
    conn.commit()


def top(conn: Connection, limit: int, min_searches: int) -> list[dict]:
    # "Huevo" y "Huevos" son la misma búsqueda: se agrupan por la forma en singular
    # (se quita la "s" final de las palabras de 5 o más letras), se suman sus
    # conteos y se muestra la forma que más se buscó.
    rows = conn.execute(
        text(
            """
            SELECT (array_agg(display ORDER BY searches DESC))[1] AS term,
                   SUM(searches)::int AS searches
            FROM search_terms
            GROUP BY regexp_replace(term, '([a-z]{4})s\\y', '\\1', 'g')
            HAVING SUM(searches) >= :min_searches
            ORDER BY SUM(searches) DESC, MAX(last_searched_at) DESC
            LIMIT :limit
            """
        ),
        {"limit": limit, "min_searches": min_searches},
    ).mappings().all()
    return [dict(r) for r in rows]
