"""Consulta por código de barras (base del módulo de realidad aumentada)."""
import pytest

from app.core.exceptions import InvalidParameterError, NotFoundError
from app.core.product_ref import ProductRef
from app.services import product_service as svc

EAN_OREO_13 = "7622300722470"
EAN_OREO_14 = "07622300722470"


def test_ean13_valido_se_busca_con_clave_de_14_digitos(monkeypatch):
    visto = {}

    def buscar(conn, ean14):
        visto["ean"] = ean14
        return ProductRef(kind="canonical", numeric_id=10953)

    monkeypatch.setattr(svc.product_repository, "find_ref_by_ean", buscar)
    monkeypatch.setattr(svc, "compare_product", lambda conn, pid, codes=None: ("comparado", pid, codes))

    assert svc.compare_by_ean(None, EAN_OREO_13, ["EXITO"]) == ("comparado", "p-10953", ["EXITO"])
    assert visto["ean"] == EAN_OREO_14


def test_producto_sin_homologar_se_resuelve_como_source(monkeypatch):
    monkeypatch.setattr(svc.product_repository, "find_ref_by_ean",
                        lambda conn, ean14: ProductRef(kind="source", numeric_id=77))
    monkeypatch.setattr(svc, "compare_product", lambda conn, pid, codes=None: pid)
    assert svc.compare_by_ean(None, EAN_OREO_13) == "sp-77"


@pytest.mark.parametrize("malo", ["7622300722471", "123", "abc", "2000000012345", ""])
def test_codigo_invalido_es_error_400(monkeypatch, malo):
    monkeypatch.setattr(svc.product_repository, "find_ref_by_ean",
                        lambda *a, **k: pytest.fail("no debe consultar la base con un código inválido"))
    with pytest.raises(InvalidParameterError):
        svc.compare_by_ean(None, malo)


def test_codigo_valido_pero_desconocido_es_404(monkeypatch):
    monkeypatch.setattr(svc.product_repository, "find_ref_by_ean", lambda conn, ean14: None)
    with pytest.raises(NotFoundError):
        svc.compare_by_ean(None, EAN_OREO_13)
