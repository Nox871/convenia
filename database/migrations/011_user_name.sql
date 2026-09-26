-- Nombre para mostrar del usuario (saludo y perfil). Opcional: las cuentas
-- creadas antes de esta migración no lo tienen; se completa con el nombre
-- que entrega Google al iniciar sesión, o lo edita el propio usuario.
ALTER TABLE users ADD COLUMN IF NOT EXISTS name TEXT;
