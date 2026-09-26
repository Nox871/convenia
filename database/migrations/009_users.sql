-- Cuentas de usuario, para reemplazar el identificador anónimo de
-- dispositivo (owner_ref) por una sesión real que sobrevive a un cambio de
-- teléfono o una reinstalación de la app.
--
-- password_hash y google_sub son AMBOS nullable a propósito, pero nunca
-- los dos a la vez (constraint CHECK): un usuario se registra con correo y
-- contraseña (password_hash lleno, google_sub nulo) o con Google Sign-In
-- (google_sub lleno, password_hash nulo). password_hash nunca guarda la
-- contraseña real, sólo el resultado de bcrypt -- irreversible incluso
-- para quien tenga acceso directo a la base de datos.
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT,
    google_sub TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_tiene_un_metodo_de_acceso
        CHECK (password_hash IS NOT NULL OR google_sub IS NOT NULL)
);

-- Las listas existentes (ligadas a owner_ref) se conservan tal cual; user_id
-- queda nullable para no romper nada, y se irá poblando a medida que la app
-- incorpore el inicio de sesión. owner_ref se mantiene como respaldo para
-- quien use la app sin crear cuenta.
ALTER TABLE shopping_lists
    ADD COLUMN IF NOT EXISTS user_id BIGINT REFERENCES users(id);

CREATE INDEX IF NOT EXISTS idx_shopping_lists_user_id ON shopping_lists (user_id);
