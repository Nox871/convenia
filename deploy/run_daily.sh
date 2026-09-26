#!/usr/bin/env bash
# Corrida diaria de Convenia: scrapers (en 3 carriles) -> ETL -> homologación.
# Un fallo en un supermercado se registra y no detiene a los demás.
set -u

ROOT="$HOME/convenia"
PY="$ROOT/scraper/.venv/bin/python"
LOGDIR="$ROOT/logs/$(date +%F)"
mkdir -p "$LOGDIR"
: > "$LOGDIR/.fallos"

log() { echo "[$(date '+%F %T')] $*"; }

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

# Éxito y Carulla son los más grandes: cada uno tiene su carril. Los más
# pequeños comparten el tercero. Tres navegadores a la vez caben en 4 GB.
( run_scraper exito ) &
( run_scraper carulla ) &
( run_scraper d1; run_scraper jumbo; run_scraper olimpica ) &
wait

FALLOS=$(wc -l < "$LOGDIR/.fallos")

cd "$ROOT" || exit 1

log "ETL: inicio"
"$PY" -m etl.run_etl ALL > "$LOGDIR/etl.log" 2>&1 || { log "ETL: FALLÓ (ver $LOGDIR/etl.log)"; FALLOS=$((FALLOS + 1)); }

log "Homologación: inicio"
"$PY" -m etl.homologacion.run > "$LOGDIR/homologacion.log" 2>&1 || { log "Homologación: FALLÓ (ver $LOGDIR/homologacion.log)"; FALLOS=$((FALLOS + 1)); }

log "== Fin de la corrida (fallos: $FALLOS) =="
[ "$FALLOS" -eq 0 ]
