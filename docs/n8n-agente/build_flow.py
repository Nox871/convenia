import json

SISTEMA = """Eres ConveniaBot, el asistente de Convenia, una aplicación móvil que ayuda a decidir en qué supermercado comprar. Hablas en español, con un tono amable y breve (máximo 6 líneas por respuesta).

QUÉ ES CONVENIA
- Compara precios de productos entre supermercados de Bucaramanga (D1, Éxito, Jumbo; Carulla y Olímpica tienen precios, pero sus tiendas no están en el rango).
- Permite armar listas de compra con presupuesto, ver cómo repartir la compra entre tiendas, consultar el historial de precios por mes y ver las tiendas cercanas con distancia y tiempo.
- Se puede buscar por texto, por voz o con una foto de la lista.
- Datos de referencia (corte del 13 de octubre de 2026): 47.199 productos, 339.892 precios, 10.799 productos únicos; 6.119 se comparan en 2 o más supermercados.
- En una lista de prueba de 5 productos, repartir la compra entre Carulla y Éxito costó $106.885 frente a $117.390 comprando todo en Éxito: $10.505 menos. El ahorro depende de la lista y de la cercanía de las tiendas.

REGLAS
1. Responde solo sobre Convenia, precios de supermercados y cómo usar la aplicación. Si preguntan otra cosa, di amablemente que solo puedes ayudar con eso.
2. Nunca inventes precios. Si no tienes un dato, di que no lo tienes. Los precios que menciones deben venir de la herramienta de consulta o de los datos de referencia de arriba.
3. Si la herramienta de consulta está disponible, úsala para buscar productos y precios antes de responder sobre un producto concreto, y menciona la tienda y el precio.
4. Si el usuario pide comparar, explica cuál tienda conviene y por qué, y recuerda que falta sumar el costo del traslado.
5. Si te saludan, preséntate en una línea y ofrece ayuda."""

nodes = [
    {"parameters": {"content": "## ConveniaBot (n8n + Telegram)\nPráctica: agente de IA con chatbot interactivo.\n\nFlujo: Telegram Trigger → AI Agent (Gemini + memoria por chat + herramientas opcionales) → Telegram.\n\nAntes de activar: asignar credenciales de Telegram y de Google Gemini. Las herramientas HTTP vienen desactivadas; se activan si el backend de Convenia está en ejecución.", "height": 260, "width": 420},
     "id": "n-nota", "name": "Nota", "type": "n8n-nodes-base.stickyNote", "typeVersion": 1, "position": [-80, -40]},
    {"parameters": {"updates": ["message"], "additionalFields": {}},
     "id": "n-trigger", "name": "Telegram Trigger", "type": "n8n-nodes-base.telegramTrigger", "typeVersion": 1.1, "position": [400, 300], "webhookId": "convenia-bot-webhook"},
    {"parameters": {"promptType": "define", "text": "={{ $json.message.text }}", "options": {"systemMessage": SISTEMA}},
     "id": "n-agent", "name": "ConveniaBot (AI Agent)", "type": "@n8n/n8n-nodes-langchain.agent", "typeVersion": 1.7, "position": [680, 300]},
    {"parameters": {"modelName": "models/gemini-3.5-flash-lite", "options": {"temperature": 0.3}},
     "id": "n-llm", "name": "Google Gemini Chat Model", "type": "@n8n/n8n-nodes-langchain.lmChatGoogleGemini", "typeVersion": 1, "position": [560, 560]},
    {"parameters": {"sessionIdType": "customKey", "sessionKey": "={{ $('Telegram Trigger').item.json.message.chat.id }}", "contextWindowLength": 8},
     "id": "n-mem", "name": "Memoria por chat", "type": "@n8n/n8n-nodes-langchain.memoryBufferWindow", "typeVersion": 1.3, "position": [740, 560]},
    {"parameters": {"toolDescription": "Busca productos y sus precios por supermercado en la base de datos de Convenia. Úsala cuando el usuario pregunte por el precio o la disponibilidad de un producto (por ejemplo arroz, leche, huevos).",
                    "method": "GET", "url": "http://host.docker.internal:8000/api/v1/products", "sendQuery": True,
                    "parametersQuery": {"values": [{"name": "q", "valueProvider": "modelRequired", "description": "Texto del producto a buscar, en español y en singular si es posible."},
                                                   {"name": "limit", "value": "5"}]}},
     "id": "n-tool1", "name": "Buscar productos (API Convenia)", "type": "@n8n/n8n-nodes-langchain.toolHttpRequest", "typeVersion": 1.1, "position": [920, 560], "disabled": True},
    {"parameters": {"chatId": "={{ $('Telegram Trigger').item.json.message.chat.id }}", "text": "={{ $json.output }}", "additionalFields": {"appendAttribution": False}},
     "id": "n-send", "name": "Responder en Telegram", "type": "n8n-nodes-base.telegram", "typeVersion": 1.2, "position": [1040, 300]},
]
conn = {
    "Telegram Trigger": {"main": [[{"node": "ConveniaBot (AI Agent)", "type": "main", "index": 0}]]},
    "ConveniaBot (AI Agent)": {"main": [[{"node": "Responder en Telegram", "type": "main", "index": 0}]]},
    "Google Gemini Chat Model": {"ai_languageModel": [[{"node": "ConveniaBot (AI Agent)", "type": "ai_languageModel", "index": 0}]]},
    "Memoria por chat": {"ai_memory": [[{"node": "ConveniaBot (AI Agent)", "type": "ai_memory", "index": 0}]]},
    "Buscar productos (API Convenia)": {"ai_tool": [[{"node": "ConveniaBot (AI Agent)", "type": "ai_tool", "index": 0}]]},
}
wf = {"name": "ConveniaBot - agente en Telegram", "nodes": nodes, "connections": conn, "active": False,
      "settings": {"executionOrder": "v1"}, "meta": {"templateCredsSetupCompleted": False}}
json.dump(wf, open("Convenia_Agente_n8n.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open("system_prompt.txt", "w", encoding="utf-8").write(SISTEMA)
print("ok", len(SISTEMA), "caracteres")
