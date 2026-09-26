-- Momento en que la persona aceptó el tratamiento de sus datos personales
-- (Ley 1581 de 2012, Habeas Data). Las cuentas anteriores a esta migración
-- quedan en NULL: se crearon antes de que la app registrara el consentimiento.
ALTER TABLE users ADD COLUMN IF NOT EXISTS consent_at TIMESTAMPTZ;
