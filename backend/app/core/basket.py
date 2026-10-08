"""Armado de una lista de compras para un presupuesto y un nivel de gasto.

Lógica pura (sin base de datos): recibe, por cada término de la lista, los
productos candidatos con su precio, y decide qué producto y cuántas unidades
llevar para que el total quepa en el presupuesto y sea lo más provechoso.

Reglas:
  * El ORDEN de los términos es su prioridad: lo primero es lo más importante.
  * Nivel: "economico" (precios bajos), "medio" y "alto" (marcas más caras).
    Se elige por posición en el ranking de precios entre productos conocidos.
  * Con presupuesto: se parte de lo más económico para todo; si ni así cabe, se
    quitan productos, empezando por los de menor prioridad. Con lo que sobra se
    mejora de nivel, un escalón por vuelta y por prioridad, hasta el nivel pedido,
    y después se llevan más unidades.
  * Nunca se supera el presupuesto, salvo que el primer producto solo ya lo
    exceda (entonces se avisa en `excede_presupuesto`).
"""
from __future__ import annotations

from dataclasses import dataclass, field

NIVELES = ("economico", "medio", "alto")
_POSICION = {"economico": 0.1, "medio": 0.5, "alto": 0.85}
CANTIDAD_MAXIMA = 4


@dataclass
class Candidato:
    id: str
    name: str
    price: float
    offers_count: int = 1
    data: dict = field(default_factory=dict)  # lo demás que el llamador quiera conservar


@dataclass
class Linea:
    termino: str
    candidato: Candidato | None
    cantidad: int = 1
    nivel_indice: int = 1

    @property
    def subtotal(self) -> float:
        return 0.0 if self.candidato is None else self.candidato.price * self.cantidad


@dataclass
class Canasta:
    nivel_pedido: str
    nivel_usado: str
    presupuesto: float | None
    lineas: list[Linea]
    sin_presupuesto_para: list[str]
    excede_presupuesto: bool

    @property
    def total(self) -> float:
        return sum(l.subtotal for l in self.lineas if l.candidato is not None)

    @property
    def sobrante(self) -> float | None:
        return None if self.presupuesto is None else self.presupuesto - self.total


def elegir(candidatos: list[Candidato], nivel: str) -> Candidato | None:
    """Producto que representa a un nivel de gasto entre los candidatos de un término."""
    validos = [c for c in candidatos if c.price and c.price > 0]
    if not validos:
        return None
    # Los que se venden en 2+ supermercados son los conocidos y comparables; si hay
    # suficientes se ignoran los demás (marcas sueltas, presentaciones raras).
    conocidos = [c for c in validos if c.offers_count >= 2]
    base = conocidos if len(conocidos) >= 3 else validos
    ordenados = sorted(base, key=lambda c: (c.price, c.name))
    posicion = _POSICION.get(nivel, 0.5)
    indice = round(posicion * (len(ordenados) - 1))
    return ordenados[indice]


def armar(
    candidatos_por_termino: list[tuple[str, list[Candidato]]],
    nivel: str = "medio",
    presupuesto: float | None = None,
) -> Canasta:
    """Arma la canasta. `candidatos_por_termino` va en orden de prioridad."""
    if nivel not in NIVELES:
        nivel = "medio"
    tope = NIVELES.index(nivel)

    def en_nivel(candidatos: list[Candidato], indice: int) -> Candidato | None:
        return elegir(candidatos, NIVELES[indice])

    # Sin presupuesto: todo en el nivel pedido, una unidad de cada uno.
    if presupuesto is None:
        lineas = [Linea(t, en_nivel(c, tope), nivel_indice=tope) for t, c in candidatos_por_termino]
        return Canasta(nivel, nivel, None, lineas, [], False)

    candidatos = dict(candidatos_por_termino)

    # 1) se parte de lo más económico para todo
    lineas = [Linea(t, en_nivel(c, 0), nivel_indice=0) for t, c in candidatos_por_termino]

    def total_actual() -> float:
        return sum(l.subtotal for l in lineas)

    # 2) si ni así cabe, se quitan los de menor prioridad
    quitados: list[str] = []
    excede = False
    while total_actual() > presupuesto:
        con_producto = [l for l in lineas if l.candidato is not None]
        if len(con_producto) <= 1:
            excede = True
            break
        ultimo = con_producto[-1]
        quitados.append(ultimo.termino)
        lineas.remove(ultimo)

    if not excede:
        # 3) con lo que sobra, se sube de nivel UN escalón por vuelta y por prioridad
        #    (lo primero mejora antes), hasta el nivel pedido y sin pasarse
        cambio = True
        while cambio:
            cambio = False
            for l in lineas:
                if l.candidato is None or l.nivel_indice >= tope:
                    continue
                mejor = en_nivel(candidatos[l.termino], l.nivel_indice + 1)
                if mejor is None or mejor.price <= l.candidato.price:
                    l.nivel_indice += 1  # no hay nada distinto en ese escalón: se salta
                    cambio = True
                    continue
                extra = (mejor.price - l.candidato.price) * l.cantidad
                if total_actual() + extra <= presupuesto:
                    l.candidato = mejor
                    l.nivel_indice += 1
                    cambio = True

        # 4) y si aún sobra, se llevan más unidades, por prioridad
        cambio = True
        while cambio:
            cambio = False
            for l in lineas:
                if l.candidato is None or l.cantidad >= CANTIDAD_MAXIMA:
                    continue
                if total_actual() + l.candidato.price <= presupuesto:
                    l.cantidad += 1
                    cambio = True

    niveles = {l.nivel_indice for l in lineas if l.candidato is not None}
    if len(niveles) == 1:
        usado = NIVELES[niveles.pop()]
    else:
        usado = "mixto"
    return Canasta(
        nivel_pedido=nivel,
        nivel_usado=usado,
        presupuesto=presupuesto,
        lineas=lineas,
        sin_presupuesto_para=quitados,
        excede_presupuesto=excede,
    )
