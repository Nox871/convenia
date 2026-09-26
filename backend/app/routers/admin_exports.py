from datetime import date

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.engine import Connection

from app.core.database import get_db
from app.routers.auth import require_admin
from app.services import export_service

router = APIRouter(prefix="/api/v1/admin/exports", tags=["admin"])


@router.get("/price-history")
def export_price_history(
    supermarket: str | None = Query(None, description="Código de supermercado; vacío = todos"),
    days: int = Query(30, ge=1, le=3650, description="Cuántos días hacia atrás incluir"),
    conn: Connection = Depends(get_db),
    _admin=Depends(require_admin),
):
    """Historial de precios en CSV (una fila por observación). Sólo administradores."""
    code, _total = export_service.prepare_price_history_export(conn, supermarket, days)
    filename = f"convenia_historial_{(code or 'todos').lower()}_{date.today().isoformat()}.csv"
    return StreamingResponse(
        export_service.iter_price_history_csv(code, days),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
