#!/usr/bin/env bash
# Corrida diaria de Convenia: respaldo -> scrapers (en 3 carriles) -> ETL ->
# homologación. Un fallo en un supermercado se registra y no detiene a los
# demás.
set -u

# Se calcula a partir de la ubicación real del script (no de $HOME): systemd
# no define $HOME para un servicio con `User=` salvo que se lo pidas
# explícitamente, así que "$HOME/convenia" quedaba apuntando a una ruta
# inexistente y el script fallaba en silencio antes de escribir ningún log.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/scraper/.venv/bin/python"
INICIO_EPOCH=$(date +%s)
LOGDIR="$ROOT/logs/$(date +%F)"
BACKUPDIR="$ROOT/backups"
mkdir -p "$LOGDIR" "$BACKUPDIR"
: > "$LOGDIR/.fallos"

log() { echo "[$(date '+%F %T')] $*"; }

# Éxito, Carulla, Olímpica y Jumbo: no abrir la página de cada producto (sólo
# aportaba métodos de pago promocionales y costaba 8-13 s por producto). D1 no
# lo lee: ahí la visita sí es necesaria.
export SCRAPER_ENRIQUECER_PDP=0

# Que cada línea llegue al log al instante (si no, Python la guarda en memoria
# y el log parece vacío mientras el scraper trabaja).
export PYTHONUNBUFFERED=1

# Evita que dos corridas se pisen si una manual coincide con la del timer, o
# si la anterior no terminó a tiempo.
exec 9>"$ROOT/deploy/.run_daily.lock"
if ! flock -n 9; then
  log "Ya hay una corrida en curso; se omite esta."
  exit 0
fi

# Un scraper por vez dentro de su carril; su salida va a su propio log.
run_scraper() {
  local s="$1"
  log "Scraper $s: inicio"
  if (cd "$ROOT/scraper" && timeout 6h "$PY" -m "connectors.$s.scraper" > "$LOGDIR/scraper_$s.log" 2>&1); then
    log "Scraper $s: OK"
  else
    log "Scraper $s: FALLÓ (ver $LOGDIR/scraper_$s.log)"
    echo "$s" >> "$LOGDIR/.fallos"
  fi
}

log "== Inicio de la corrida diaria =="

# Respaldo antes de tocar nada: si algo sale mal en la carga de hoy, se puede
# volver al estado de ayer. Se guardan los últimos 7 días y se borra el resto.
log "Respaldo de la base de datos"
set -a; . "$ROOT/.env"; set +a
if PGPASSWORD="$DB_PASSWORD" pg_dump -h "${DB_HOST:-localhost}" -p "${DB_PORT:-5432}" -U "$DB_USER" -Fc \
     -f "$BACKUPDIR/convenia_$(date +%F).dump" "$DB_NAME" 2>"$LOGDIR/backup.log"; then
  log "Respaldo OK"
  find "$BACKUPDIR" -name 'convenia_*.dump' -mtime +7 -delete
else
  log "Respaldo FALLÓ (ver $LOGDIR/backup.log); se continúa igual"
  FALLOS_BACKUP=1
fi

# Éxito y Carulla son los más grandes: cada uno tiene su carril. Los más
# pequeños comparten el tercero. Tres navegadores a la vez caben en 4 GB.
( run_scraper exito ) &
( run_scraper carulla ) &
( run_scraper d1; run_scraper jumbo; run_scraper olimpica ) &
wait

FALLOS=$(($(wc -l < "$LOGDIR/.fallos") + ${FALLOS_BACKUP:-0}))

cd "$ROOT" || exit 1

# Migraciones pendientes de la base (idempotente: sólo aplica las que faltan).
# El ETL escribe columnas nuevas (p. ej. `ean`); sin esto fallaría completo.
log "Migraciones de base de datos"
if "$PY" database/run_migrations.py > "$LOGDIR/migraciones.log" 2>&1; then
  log "Migraciones: OK"
else
  log "Migraciones FALLARON (ver $LOGDIR/migraciones.log)"
  FALLOS=$((FALLOS + 1))
  MIGRACIONES_FALLO=1
fi

log "ETL: inicio"
if timeout 2h "$PY" -m etl.run_etl ALL > "$LOGDIR/etl.log" 2>&1; then
  log "ETL: OK"
else
  log "ETL: FALLÓ o se pasó de 2h (ver $LOGDIR/etl.log)"
  FALLOS=$((FALLOS + 1))
  ETL_FALLO=1
fi

log "Homologación: inicio"
# Sin límite de páginas, el catálogo de hoy es más grande: la comparación
# dentro de cada categoría amigable puede tardar más. 3h de techo, muy por
# encima de lo esperado, sólo para que una corrida colgada no bloquee la de
# mañana (el candado de arriba ya evita que se pisen).
if timeout 3h "$PY" -m etl.homologacion.run > "$LOGDIR/homologacion.log" 2>&1; then
  log "Homologación: OK"
else
  log "Homologación: FALLÓ o se pasó de 3h (ver $LOGDIR/homologacion.log)"
  FALLOS=$((FALLOS + 1))
  HOMOLOGACION_FALLO=1
fi

log "== Fin de la corrida (fallos: $FALLOS) =="

# ---- Aviso por correo: siempre se envía, salga bien o mal. ----
{
  echo "Corrida diaria de Convenia -- $(date '+%F %T')"
  echo
  echo "Resultado general: $([ "$FALLOS" -eq 0 ] && echo "OK, sin fallos" || echo "$FALLOS fallo(s)")"
  echo
  echo "Respaldo de la base de datos: $([ "${FALLOS_BACKUP:-0}" = 0 ] && echo OK || echo FALLÓ)"
  echo
  echo "Scrapers:"
  for s in exito carulla d1 jumbo olimpica; do
    if grep -qx "$s" "$LOGDIR/.fallos" 2>/dev/null; then
      echo "  - $s: FALLÓ"
    else
      incompletas=$(grep -h "Categorías incompletas" "$LOGDIR/scraper_$s.log" 2>/dev/null | tail -1 | tr -dc '0-9')
      if [ -n "$incompletas" ] && [ "$incompletas" -gt 0 ]; then
        echo "  - $s: OK, pero $incompletas categorías quedaron incompletas (la tienda falló al pedir páginas)"
      else
        echo "  - $s: OK"
      fi
    fi
  done
  echo
  echo "Migraciones: $([ "${MIGRACIONES_FALLO:-0}" = 0 ] && echo OK || echo FALLÓ)"
  echo "ETL: $([ "${ETL_FALLO:-0}" = 0 ] && echo OK || echo FALLÓ)"
  echo "Homologación: $([ "${HOMOLOGACION_FALLO:-0}" = 0 ] && echo OK || echo FALLÓ)"
  echo
  echo "Duración de la corrida: $(( ($(date +%s) - INICIO_EPOCH) / 60 )) min"
  echo "Disco libre en el servidor: $(df -h --output=avail "$ROOT" | tail -1 | tr -d ' ')"
  echo
  "$PY" "$ROOT/deploy/resumen_datos.py" 2>&1 || true
  echo
  echo "Logs completos en el servidor: $LOGDIR"
} > "$LOGDIR/resumen.txt"

ASUNTO="Convenia $(date +%F): $([ "$FALLOS" -eq 0 ] && echo "corrida OK" || echo "$FALLOS fallo(s)")"
"$PY" "$ROOT/deploy/send_alert.py" "$ASUNTO" < "$LOGDIR/resumen.txt" \
  || log "No se pudo enviar el correo de aviso (ver arriba)."

[ "$FALLOS" -eq 0 ]
