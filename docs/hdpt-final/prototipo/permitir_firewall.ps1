# Abre en el Firewall de Windows SOLO los puertos que necesita el celular, y solo en redes PRIVADAS:
#   8000 = API de Convenia     5678 = asistente ConveniaBot (n8n)
# Hay que ejecutarlo UNA VEZ como Administrador (clic derecho en PowerShell > Ejecutar como administrador):
#   powershell -ExecutionPolicy Bypass -File permitir_firewall.ps1
# Para quitarlo despues:  Remove-NetFirewallRule -DisplayName "Convenia (API y asistente)"
New-NetFirewallRule -DisplayName "Convenia (API y asistente)" -Direction Inbound -Protocol TCP -LocalPort 8000,5678 -Action Allow -Profile Private
Write-Host "Listo. Tambien confirme que la red Wi-Fi este marcada como 'Privada' en Configuracion > Red e Internet."
