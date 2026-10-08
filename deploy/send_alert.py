#!/usr/bin/env python3
"""Envía el correo de aviso de la corrida diaria (éxito o fallo) por Gmail SMTP.

Sólo usa la librería estándar (smtplib), así que corre con cualquiera de los
dos venvs del proyecto sin instalar nada nuevo.

Uso:
    echo "cuerpo del correo" | python send_alert.py "Asunto"

Variables de entorno requeridas (ya las carga run_daily.sh desde .env):
    ALERT_EMAIL_TO             a quién avisar (ej. tu_correo@gmail.com)
    ALERT_EMAIL_FROM           cuenta de Gmail que envía
    ALERT_EMAIL_APP_PASSWORD   contraseña de aplicación de esa cuenta
                                (Cuenta de Google > Seguridad > Verificación en
                                dos pasos > Contraseñas de aplicaciones)

Si falta alguna variable, o el envío falla (sin internet, credencial
vencida), termina con error pero NUNCA lanza una excepción sin capturar: un
correo que no se pudo enviar no debe hacer fallar la corrida diaria completa.
"""
from __future__ import annotations

import os
import smtplib
import sys
from email.mime.text import MIMEText
from email.utils import formatdate


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: send_alert.py <asunto> (el cuerpo se lee de stdin)", file=sys.stderr)
        return 2

    subject = sys.argv[1]
    body = sys.stdin.read()

    to_addr = os.environ.get("ALERT_EMAIL_TO")
    from_addr = os.environ.get("ALERT_EMAIL_FROM")
    app_password = os.environ.get("ALERT_EMAIL_APP_PASSWORD")
    if not (to_addr and from_addr and app_password):
        print(
            "Faltan ALERT_EMAIL_TO / ALERT_EMAIL_FROM / ALERT_EMAIL_APP_PASSWORD en el entorno; "
            "no se envía correo.",
            file=sys.stderr,
        )
        return 1

    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_addr
    msg["Date"] = formatdate(localtime=True)

    try:
        with smtplib.SMTP("smtp.gmail.com", 587, timeout=30) as server:
            server.starttls()
            server.login(from_addr, app_password)
            server.sendmail(from_addr, [to_addr], msg.as_string())
    except Exception as exc:  # noqa: BLE001 - un correo fallido no debe tumbar la corrida
        print(f"No se pudo enviar el correo de aviso: {exc}", file=sys.stderr)
        return 1

    print(f"Correo enviado a {to_addr}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
