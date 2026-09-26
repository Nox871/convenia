import pytest

from app.core.exceptions import ForbiddenError
from app.core.ownership import account_owner_ref, resolve_owner_ref, user_id_from_owner_ref


def test_con_sesion_el_dueno_es_la_cuenta_aunque_el_cliente_mande_otro_dispositivo():
    assert resolve_owner_ref("un-dispositivo", 7) == "user:7"


def test_con_sesion_no_se_puede_pedir_las_listas_de_otra_cuenta():
    # El cliente manda "user:5" pero la sesión es de la cuenta 7.
    assert resolve_owner_ref("user:5", 7) == "user:7"


def test_sin_sesion_el_dueno_es_el_dispositivo():
    assert resolve_owner_ref("1810c12a-c115-48e7", None) == "1810c12a-c115-48e7"


def test_un_invitado_no_puede_hacerse_pasar_por_una_cuenta():
    with pytest.raises(ForbiddenError):
        resolve_owner_ref("user:5", None)


def test_id_de_cuenta_desde_el_dueno():
    assert user_id_from_owner_ref(account_owner_ref(42)) == 42
    assert user_id_from_owner_ref("1810c12a-c115") is None
    assert user_id_from_owner_ref("user:abc") is None
