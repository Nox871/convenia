# Compila el APK de Convenia para un CELULAR REAL: apunta a la dirección de esta computadora en la red.
# El celular y la computadora deben estar en la misma red Wi-Fi (o la computadora conectada al punto de
# acceso del celular). Si cambia de red, la dirección cambia y hay que volver a compilar.
# Uso:  powershell -ExecutionPolicy Bypass -File compilar_apk_celular.ps1            (detecta la dirección sola)
#       powershell -ExecutionPolicy Bypass -File compilar_apk_celular.ps1 -Ip 192.168.1.46
param([string]$Ip, [switch]$Debug)
$ErrorActionPreference = "Stop"
$raiz = $null
foreach ($c in @($env:CONVENIA_RAIZ, (Join-Path $PSScriptRoot "..\..\.."), "E:\convenia")) {
    if ($c -and (Test-Path (Join-Path $c "mobile\pubspec.yaml"))) { $raiz = (Resolve-Path $c).Path; break }
}
if (-not $raiz) { throw "No encuentro la carpeta del proyecto. Defina CONVENIA_RAIZ." }
if (-not $Ip) {
    $Ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|Wireless|Ethernet' -and $_.IPAddress -notmatch '^(127|169\.254|172\.28|192\.168\.56)\.' } | Select-Object -First 1).IPAddress
}
if (-not $Ip) { throw "No pude detectar la dirección de la red. Use -Ip 192.168.x.x" }
Write-Host "Compilando para el celular, apuntando a http://${Ip}:8000 (API) y http://${Ip}:5678 (asistente)..."
$modo = if ($Debug) { "--debug" } else { "--release" }
Push-Location (Join-Path $raiz "mobile")
flutter pub get
flutter build apk $modo "--dart-define=API_BASE_URL=http://${Ip}:8000" "--dart-define=ASSISTANT_URL=http://${Ip}:5678/webhook/convenia-chat-webhook/chat"
Pop-Location
$origen = Join-Path $raiz ("mobile\build\app\outputs\flutter-apk\app-" + ($modo -replace '--','') + ".apk")
$destino = Join-Path $PSScriptRoot "Convenia_celular.apk"
Copy-Item $origen $destino -Force
Write-Host "Listo: $destino"
Write-Host "Páselo al celular (cable USB, Drive o WhatsApp) e instálelo permitiendo 'instalar apps de origen desconocido'."
