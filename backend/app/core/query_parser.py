"""Interpreta lo que escribe la persona al buscar: separa las PALABRAS del
producto de la PRESENTACIÓN que pide ("huevos 30 und", "café 500", "leche 1 litro").

La presentación no se exige (si nadie la vende, igual se muestra lo demás): se
usa para poner primero los productos que sí la traen. Las palabras, en cambio,
deben aparecer todas en el nombre, en cualquier orden.

Lógica pura, sin base de datos, para poder probarla.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

_UNIDADES_CONTEO = {"und", "unds", "ud", "uds", "un", "unid", "unidad", "unidades", "u"}
_GRAMOS = {"g", "gr", "grs", "gramo", "gramos"}
_KILOS = {"kg", "kgs", "kilo", "kilos"}
_MILILITROS = {"ml", "cc"}
_LITROS = {"l", "lt", "lts", "litro", "litros"}
_LIBRAS = {"lb", "lbs", "libra", "libras"}
_TODAS_LAS_UNIDADES = _UNIDADES_CONTEO | _GRAMOS | _KILOS | _MILILITROS | _LITROS | _LIBRAS

_RELLENO = {"de", "del", "la", "el", "las", "los", "x", "y", "con", "para", "en", "por"}

_UNIDAD_REGEX = {
    "g": r"(?:g|gr|grs|gramos?)",
    "kg": r"(?:kg|kgs|kilos?)",
    "ml": r"(?:ml|cc)",
    "l": r"(?:l|lt|lts|litros?)",
}

_TOKEN = re.compile(r"\d+(?:[.,]\d+)?|[a-z]+")


def sin_tildes(texto: str) -> str:
    nfd = unicodedata.normalize("NFD", texto.lower())
    return "".join(c for c in nfd if unicodedata.category(c) != "Mn")


@dataclass
class ConsultaParseada:
    palabras: list[str] = field(default_factory=list)
    cantidad_regex: str | None = None
    cantidad_texto: str | None = None

    @property
    def texto(self) -> str:
        return " ".join(self.palabras)


def _numero(token: str) -> float:
    return float(token.replace(",", "."))


def _regex_numero(valor: float) -> str:
    if valor == int(valor):
        return str(int(valor))
    texto = f"{valor:.3f}".rstrip("0").rstrip(".")
    return texto.replace(".", r"[.,]")


def _alternativas(valor: float, unidad: str | None) -> list[str]:
    """Fragmentos de regex (sobre el nombre sin tildes) que reconocen esa presentación."""
    n = _regex_numero(valor)
    sin_unidad = rf"{n}(?![0-9]|[.,][0-9])"
    if unidad is None or unidad == "und":
        return [sin_unidad]
    if unidad == "g":
        return [rf"{n}\s*{_UNIDAD_REGEX['g']}\b", rf"{_regex_numero(valor / 1000)}\s*{_UNIDAD_REGEX['kg']}\b"]
    if unidad == "kg":
        return [rf"{n}\s*{_UNIDAD_REGEX['kg']}\b", rf"{_regex_numero(valor * 1000)}\s*{_UNIDAD_REGEX['g']}\b"]
    if unidad == "ml":
        return [rf"{n}\s*{_UNIDAD_REGEX['ml']}\b", rf"{_regex_numero(valor / 1000)}\s*{_UNIDAD_REGEX['l']}\b"]
    if unidad == "l":
        return [rf"{n}\s*{_UNIDAD_REGEX['l']}\b", rf"{_regex_numero(valor * 1000)}\s*{_UNIDAD_REGEX['ml']}\b"]
    if unidad == "lb":
        return [rf"{_regex_numero(valor * 500)}\s*{_UNIDAD_REGEX['g']}\b", rf"{_regex_numero(valor / 2)}\s*{_UNIDAD_REGEX['kg']}\b"]
    return [sin_unidad]


def _clase(token: str) -> str | None:
    if token in _UNIDADES_CONTEO:
        return "und"
    if token in _GRAMOS:
        return "g"
    if token in _KILOS:
        return "kg"
    if token in _MILILITROS:
        return "ml"
    if token in _LITROS:
        return "l"
    if token in _LIBRAS:
        return "lb"
    return None


def interpretar(consulta: str) -> ConsultaParseada:
    """Separa palabras y presentación. Si no hay palabras (sólo números),
    devuelve las palabras vacías y el llamador usa el texto original."""
    tokens = _TOKEN.findall(sin_tildes(consulta or ""))
    palabras: list[str] = []
    alternativas: list[str] = []
    descripcion: list[str] = []

    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t[0].isdigit():
            valor = _numero(t)
            unidad = None
            if i + 1 < len(tokens):
                clase = _clase(tokens[i + 1])
                if clase is not None:
                    unidad = clase
                    i += 1  # la unidad se consume junto con el número
            if valor > 0:
                alternativas.extend(_alternativas(valor, unidad))
                if unidad is None and valor >= 50:
                    # "café 500": casi siempre gramos (o ml); también vale 0,5 kg / 0,5 L.
                    alternativas.append(rf"{_regex_numero(valor / 1000)}\s*{_UNIDAD_REGEX['kg']}\b")
                    alternativas.append(rf"{_regex_numero(valor / 1000)}\s*{_UNIDAD_REGEX['l']}\b")
                descripcion.append(f"{_regex_numero(valor).replace('[.,]', ',')} {unidad or ''}".strip())
        elif t in _RELLENO or t in _TODAS_LAS_UNIDADES:
            pass
        else:
            palabras.append(t)
        i += 1

    cantidad_regex = None
    if alternativas:
        union = "|".join(alternativas)
        cantidad_regex = rf"(?:^|[^0-9.,])(?:{union})"
    return ConsultaParseada(
        palabras=palabras,
        cantidad_regex=cantidad_regex,
        cantidad_texto=", ".join(descripcion) if descripcion else None,
    )


def escapar_like(texto: str) -> str:
    """Escapa los comodines de LIKE (% _ \\) para usar el texto como literal."""
    return texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def termino_de_busqueda(consulta: str) -> tuple[str, str] | None:
    """(clave, texto a mostrar) para contar una búsqueda como frecuente, o None
    si no vale la pena contarla (muy corta, muy larga o sin palabras).

    La presentación pedida se descarta ("huevos 30 und" cuenta como "huevos"):
    lo frecuente es el producto, no cada tamaño."""
    c = interpretar(consulta)
    if not c.palabras:
        return None
    clave = c.texto
    if len(clave) < 3 or len(clave) > 40 or clave.isdigit():
        return None
    # Se muestra con las tildes que escribió la persona: la primera letra en
    # mayúscula y el resto como vino ("café" -> "Café").
    original = " ".join(re.findall(r"[^\W\d_]+", consulta.lower(), flags=re.UNICODE))
    mostrar = original if sin_tildes(original) == clave else clave
    return clave, mostrar[:1].upper() + mostrar[1:]


def patron_de_palabra(palabra: str) -> str | None:
    """Expresión regular (Postgres, sobre el nombre en minúsculas y sin tildes)
    que reconoce esa palabra EN EL NOMBRE de un producto.

    * Palabras cortas (hasta 4 letras: "pan", "sal", "gel", "papa"): palabra
      completa, con plural opcional ("papas", "panes"). Como subcadena, "pan"
      encontraba paño, empanada, Pantene y España, y "sal" a salsa y salchicha.
    * Palabras largas (5 o más): al comienzo de una palabra del nombre, así
      "huevo" encuentra "huevos" y "leche" encuentra "lechera", pero no
      "descafeinado" para "cafe".

    Devuelve None si el texto no es una palabra simple (letras y números)."""
    if not palabra or not re.fullmatch(r"[a-z0-9]+", palabra):
        return None
    inicio = r"(^|[^a-z0-9])"
    if len(palabra) <= 4:
        return rf"{inicio}{palabra}(s|es)?([^a-z0-9]|$)"
    # Plural: "huevos" también debe encontrar "Huevo de codorniz". Se busca el
    # singular como comienzo de palabra (que a su vez cubre el plural) y, en los
    # plurales en -es tras n/r/l ("jabones", "colores"), también la forma sin "es".
    base = palabra
    alternativa = None
    if palabra.endswith("s") and len(palabra) >= 5:
        base = palabra[:-1]
        if re.search(r"(on|or|al|el|il)es$", palabra) and len(palabra) >= 7:
            alternativa = palabra[:-2]
    if alternativa:
        return rf"{inicio}({base}|{alternativa})"
    return rf"{inicio}{base}"
