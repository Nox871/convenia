import pytest

from app.core import admin_list
from app.core.admin_list import correos_admin, debe_ser_admin
from app.services import auth_service


def test_se_leen_varios_formatos_de_lista():
    assert correos_admin("a@x.com, B@Y.com ;c@z.com") == {"a@x.com", "b@y.com", "c@z.com"}
    assert correos_admin("") == set()
    assert correos_admin(None) == set()
    assert correos_admin("sin-arroba, ,") == set()


def test_la_comparacion_no_distingue_mayusculas():
    assert debe_ser_admin("Jairo.Nunez@UPB.edu.co", "jairo.nunez@upb.edu.co")
    assert not debe_ser_admin("otro@upb.edu.co", "jairo.nunez@upb.edu.co")
    assert not debe_ser_admin(None, "jairo.nunez@upb.edu.co")
    assert not debe_ser_admin("jairo.nunez@upb.edu.co", "")


class _Repo:
    def __init__(self):
        self.llamadas = []

    def set_role(self, conn, user_id, role):
        self.llamadas.append((user_id, role))
        return {"id": user_id, "email": "jairo.nunez@upb.edu.co", "role": role, "name": None}


@pytest.fixture
def repo(monkeypatch):
    r = _Repo()
    monkeypatch.setattr(auth_service.user_repository, "set_role", r.set_role)
    monkeypatch.setattr(auth_service.settings, "admin_emails", "jairo.nunez@upb.edu.co")
    return r


def test_quien_esta_en_la_lista_sube_a_admin(repo):
    user = {"id": 7, "email": "jairo.nunez@upb.edu.co", "role": "user", "name": None}
    out = auth_service._aplicar_lista_de_admins(None, user)
    assert out["role"] == "admin"
    assert repo.llamadas == [(7, "admin")]


def test_quien_no_esta_en_la_lista_no_cambia(repo):
    user = {"id": 8, "email": "alguien@x.com", "role": "user", "name": None}
    assert auth_service._aplicar_lista_de_admins(None, user)["role"] == "user"
    assert repo.llamadas == []


def test_un_admin_que_ya_lo_es_no_se_vuelve_a_tocar(repo):
    user = {"id": 7, "email": "jairo.nunez@upb.edu.co", "role": "admin", "name": None}
    assert auth_service._aplicar_lista_de_admins(None, user) is user
    assert repo.llamadas == []


def test_quitar_a_alguien_de_la_lista_no_le_quita_el_rol(monkeypatch, repo):
    monkeypatch.setattr(auth_service.settings, "admin_emails", "")
    user = {"id": 7, "email": "jairo.nunez@upb.edu.co", "role": "admin", "name": None}
    assert auth_service._aplicar_lista_de_admins(None, user)["role"] == "admin"
    assert repo.llamadas == []
