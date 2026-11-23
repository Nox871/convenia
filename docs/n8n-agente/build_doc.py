from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.oxml.ns import qn
d = Document()
s = d.sections[0]; s.left_margin = s.right_margin = Cm(2.3); s.top_margin = s.bottom_margin = Cm(2)
st = d.styles["Normal"]; st.font.name = "Calibri"; st.font.size = Pt(11); st.element.rPr.rFonts.set(qn("w:eastAsia"), "Calibri")
def T(t, n=20):
    p = d.add_paragraph(); r = p.add_run(t); r.bold = True; r.font.size = Pt(n)
def H(t):
    p = d.add_paragraph(); r = p.add_run(t); r.bold = True; r.font.size = Pt(13); r.font.color.rgb = RGBColor(0xE5, 0x18, 0x5B); p.paragraph_format.space_before = Pt(10)
def P(t): d.add_paragraph(t)
def B(t): d.add_paragraph(t, style="List Bullet")
def N(t): d.add_paragraph(t, style="List Number")
def tabla(filas, anchos):
    t = d.add_table(rows=len(filas), cols=len(filas[0])); t.style = "Table Grid"
    for i, f in enumerate(filas):
        for j, x in enumerate(f):
            c = t.cell(i, j); c.width = Cm(anchos[j]); c.text = ""
            r = c.paragraphs[0].add_run(x); r.font.size = Pt(10); r.bold = (i == 0)
    d.add_paragraph()

T("Práctica: agente de IA con n8n y Telegram")
P("Proyecto: Convenia · Autor: Andrés Pascual Díaz Riera · Trabajo individual (asumo los cuatro roles: diseño del flujo, configuración, pruebas y documentación).")

H("1. Objetivo")
P("Diseñar y configurar un agente de IA en n8n, conectado a Telegram, que funcione como chatbot interactivo de Convenia: responde sobre qué es la aplicación, cómo usarla y, cuando el backend está disponible, consulta precios de productos en la base de datos.")

H("2. Diseño del flujo")
tabla([["Nodo", "Función"],
       ["Telegram Trigger", "Recibe cada mensaje que un usuario escribe al bot."],
       ["ConveniaBot (AI Agent)", "Decide cómo responder. Usa el mensaje del usuario, un mensaje de sistema con las reglas y el conocimiento de Convenia, la memoria y las herramientas."],
       ["Google Gemini Chat Model", "Modelo de lenguaje que genera la respuesta (temperatura baja, 0,3, para respuestas estables)."],
       ["Memoria por chat", "Recuerda los últimos 8 intercambios de cada chat de Telegram, usando el id del chat como clave."],
       ["Buscar productos (API Convenia)", "Herramienta opcional: consulta GET /api/v1/products?q=... del backend de Convenia. Viene desactivada."],
       ["Responder en Telegram", "Envía al mismo chat el texto que produjo el agente."]], [5, 11])
P("Flujo: Telegram Trigger → AI Agent → Responder en Telegram, con el modelo, la memoria y la herramienta conectados al agente.")

H("3. Configuración paso a paso")
N("Crear el bot en Telegram: abre @BotFather, escribe /newbot, elige un nombre y un usuario que termine en «bot». BotFather te entrega un token. Guárdalo en privado.")
N("Tener n8n: lo más simple es una cuenta de n8n Cloud (prueba gratuita). Alternativa local con Docker: docker run -it --rm -p 5678:5678 -v n8n_data:/home/node/.n8n docker.n8n.io/n8nio/n8n. Con n8n local, Telegram exige una dirección HTTPS pública, así que se necesita un túnel (por ejemplo ngrok o Cloudflare Tunnel) y arrancar n8n con la variable WEBHOOK_URL apuntando a ese túnel.")
N("Conseguir la clave del modelo: en Google AI Studio crea una API key de Gemini. Guárdala en privado.")
N("Importar el flujo: en n8n, menú de tres puntos → Import from file → Convenia_Agente_n8n.json.")
N("Crear las credenciales: en el nodo Telegram Trigger y en Responder en Telegram, crear la credencial «Telegram API» con el token de BotFather. En Google Gemini Chat Model, crear la credencial con la API key.")
N("Revisar el nombre del modelo en el nodo de Gemini. Si n8n indica que no existe, elige uno de la lista desplegable (por ejemplo, una versión flash).")
N("Pulsar «Execute workflow» o activar el flujo (interruptor Active) y escribirle al bot desde Telegram.")
P("Para activar la herramienta de precios: levanta el backend de Convenia en tu equipo (puerto 8000) y habilita el nodo «Buscar productos (API Convenia)». Si n8n corre en Docker, la dirección host.docker.internal apunta a tu equipo; si corre en la nube, no podrá alcanzar tu equipo y la herramienta debe quedar desactivada.")

H("4. Mensaje de sistema (prompt del agente)")
P("Define la identidad, el alcance y las reglas del agente. Resumen: responde solo sobre Convenia y precios de supermercados; nunca inventa precios; usa la herramienta cuando esté disponible; recuerda que el ahorro depende de la cercanía y del traslado; responde breve y en español. El texto completo está en el nodo del agente (campo System Message) y en system_prompt.txt.")

H("5. Pruebas")
tabla([["N.º", "Mensaje al bot", "Resultado esperado", "Resultado obtenido"],
       ["1", "Hola", "Se presenta como ConveniaBot y ofrece ayuda", "(completar)"],
       ["2", "¿Qué es Convenia?", "Explica en pocas líneas la comparación de precios, listas y tiendas cercanas", "(completar)"],
       ["3", "¿Cómo armo una lista con presupuesto?", "Describe el flujo: crear lista, elegir presupuesto y nivel de gasto", "(completar)"],
       ["4", "Repartir la compra entre tiendas, ¿ahorra siempre?", "Responde que depende de la lista y de la cercanía; cita el ejemplo de $10.505 y menciona el traslado", "(completar)"],
       ["5", "¿Cuál es la capital de Francia?", "Rechaza amablemente: solo atiende temas de Convenia", "(completar)"],
       ["6", "¿Cuánto cuesta el arroz en Éxito? (con la herramienta activa)", "Consulta la API y responde con tienda y precio reales", "(completar)"],
       ["7", "Pregunta un dato que no existe (precio de un producto inventado)", "Dice que no lo tiene; no inventa un precio", "(completar)"]], [1, 4.5, 6.5, 3.5])
P("Prueba de memoria: pregunta «¿Y en Jumbo?» después de una pregunta sobre un producto; el agente debe entender a qué producto te refieres.")

H("6. Evidencias para entregar")
B("Captura del flujo completo en n8n.")
B("Captura de la conversación con el bot en Telegram (casos 1 a 5 como mínimo).")
B("Este documento con la tabla de pruebas completada.")

H("7. Problemas frecuentes")
B("El bot no responde: el flujo no está activo, o la credencial de Telegram no está asignada en los dos nodos de Telegram.")
B("Error de webhook en n8n local: Telegram requiere HTTPS público; usa un túnel y WEBHOOK_URL, o n8n Cloud.")
B("Error en el nodo de Gemini: revisa la API key y el nombre del modelo.")
B("La herramienta de precios falla: el backend de Convenia no está en ejecución o n8n no puede alcanzarlo.")
d.save("Convenia_Agente_n8n_Guia.docx")
print("ok")
