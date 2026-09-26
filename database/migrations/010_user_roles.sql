-- Rol de usuario: 'user' (default) o 'admin'. El rol admin permite agregar
-- establecimientos físicos manualmente (ver /api/v1/stores POST) para
-- cubrir huecos del scraper de OpenStreetMap, y en el futuro exportar
-- historiales en CSV -- nunca se deja que cualquier usuario agregue
-- tiendas libremente, para que no se puedan inventar ubicaciones falsas.
ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_role_valido'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT users_role_valido CHECK (role IN ('user', 'admin'));
    END IF;
END $$;
