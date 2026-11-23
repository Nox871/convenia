# Levanta la demo completa de Convenia en esta computadora:
#   base de datos (Docker) -> API local (puerto 8000) -> asistente n8n (puerto 5678) -> prototipo web (puerto 8765)
# Uso:  powershell -ExecutionPolicy Bypass -File iniciar_demo.ps1
$ErrorActionPreference = "Stop"
# Raíz del proyecto (la que tiene la carpeta backend): se busca desde esta carpeta y, si el script
# se copió a otro lugar (p. ej. Proyecto_Final), se usa E:\convenia o la variable CONVENIA_RAIZ.
$raiz = $null
foreach ($c in @($env:CONVENIA_RAIZ, (Join-Path $PSScriptRoot "..\..\.."), "E:\convenia")) {
    if ($c -and (Test-Path (Join-Path $c "backend\app\main.py"))) { $raiz = (Resolve-Path $c).Path; break }
}
if (-not $raiz) { throw "No encuentro la carpeta del proyecto (backend). Defina CONVENIA_RAIZ." }
$py = Join-Path $raiz "backend\.venv\Scripts\python.exe"

# 1) Docker Desktop, base de datos y asistente (n8n)
if (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue)) {
    Start-Process "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"
}
for ($i = 0; $i -lt 60; $i++) { docker info *> $null; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep 3 }
docker start convenia-db | Out-Null
$hayN8n = docker ps -a --format '{{.Names}}' | Select-String -Pattern '^n8n$' -Quiet
if ($hayN8n) { docker start n8n | Out-Null } else { Write-Host "Aviso: no existe el contenedor n8n (ver COMO_EJECUTAR.txt, punto 7). El asistente no responderá." }
Start-Sleep 5

# 2) API (FastAPI). El .env apunta al puerto 5432; el contenedor usa el 5433.
$env:DB_HOST = "localhost"; $env:DB_PORT = "5433"; $env:DB_PASSWORD = "convenia"
$env:BACKEND_CORS_ORIGINS = "null,http://127.0.0.1:8765,http://localhost:8765"
Start-Process $py -WorkingDirectory (Join-Path $raiz "backend") -ArgumentList "-m uvicorn app.main:app --host 0.0.0.0 --port 8000"

# 3) Prototipo web servido en http://127.0.0.1:8765
Start-Process $py -WorkingDirectory $PSScriptRoot -ArgumentList "-m http.server 8765 --bind 127.0.0.1"
Start-Sleep 6
Start-Process "http://127.0.0.1:8765/Convenia_AR_prototipo.html"

# 4) Dirección de esta computadora en la red (para el celular)
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|Wireless|Ethernet' -and $_.IPAddress -notmatch '^(127|169\.254|172\.28|192\.168\.56)\.' } | Select-Object -First 1).IPAddress
Write-Host ""
Write-Host "Listo."
Write-Host "  API:        http://127.0.0.1:8000/docs"
Write-Host "  Prototipo:  http://127.0.0.1:8765/Convenia_AR_prototipo.html"
Write-Host "  Asistente:  http://localhost:5678  (chat público en /webhook/convenia-chat-webhook/chat)"
if ($ip) {
    Write-Host ""
    Write-Host "PARA EL CELULAR (misma red Wi-Fi que esta computadora): la app debe estar compilada para $ip"
    Write-Host "  Si cambió de red, recompile con:  compilar_apk_celular.ps1"
}
