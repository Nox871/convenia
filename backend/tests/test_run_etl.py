import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from etl import run_etl


def test_una_tienda_que_falla_no_impide_cargar_las_demas(monkeypatch):
    cargadas = []

    class Falso:
        def __init__(self, code, raw_dir, aceptar_tamano=False):
            self.code = code

        def run(self):
            if self.code == "JUMBO":
                raise RuntimeError("RAW sospechosamente pequeño")
            cargadas.append(self.code)

    monkeypatch.setattr(run_etl, "SupermarketETL", Falso)
    monkeypatch.setattr(sys, "argv", ["run_etl", "ALL"])
    with pytest.raises(SystemExit) as salida:
        run_etl.main()
    assert salida.value.code == 1  # el fallo se reporta...
    assert "OLIMPICA" in cargadas  # ...pero Olímpica sí se cargó, después del fallo
    assert cargadas == ["D1", "EXITO", "CARULLA", "OLIMPICA"]


def test_sin_fallos_termina_normal(monkeypatch):
    class Falso:
        def __init__(self, code, raw_dir, aceptar_tamano=False):
            pass

        def run(self):
            pass

    monkeypatch.setattr(run_etl, "SupermarketETL", Falso)
    monkeypatch.setattr(sys, "argv", ["run_etl", "ALL"])
    run_etl.main()
