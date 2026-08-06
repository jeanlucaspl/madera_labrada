-- ============================================================
-- MADERA LABRADA — Base de datos Supabase
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ============================================================

-- ── TABLA: perfiles ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perfiles (
  id              UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  nombre          TEXT NOT NULL,
  apellido        TEXT NOT NULL,
  dni             TEXT,
  rol             TEXT NOT NULL DEFAULT 'empleado' CHECK (rol IN ('admin','empleado')),
  turno           TEXT CHECK (turno IN ('mañana','tarde','noche')),
  area            TEXT,
  foto_url        TEXT,
  foto_descriptor JSONB,
  activo          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Helper: ahora sí existe perfiles, se puede crear la función
-- PL/pgSQL para que valide en tiempo de ejecución, no de compilación
CREATE OR REPLACE FUNCTION es_admin()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid() AND rol = 'admin' AND activo = true
    );
  END;
  $$;

ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "perfiles_read" ON perfiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR es_admin());

CREATE POLICY "perfiles_insert" ON perfiles FOR INSERT TO authenticated
  WITH CHECK (es_admin());

CREATE POLICY "perfiles_update" ON perfiles FOR UPDATE TO authenticated
  USING (id = auth.uid() OR es_admin());

CREATE POLICY "perfiles_delete" ON perfiles FOR DELETE TO authenticated
  USING (es_admin());

-- ── TABLA: fichajes ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fichajes (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  personal_id       UUID NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  tipo              TEXT NOT NULL CHECK (tipo IN ('entrada','salida')),
  fecha             DATE NOT NULL DEFAULT CURRENT_DATE,
  hora              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  verificado_facial BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE fichajes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fichajes_read" ON fichajes FOR SELECT TO authenticated
  USING (personal_id = auth.uid() OR es_admin());

CREATE POLICY "fichajes_insert" ON fichajes FOR INSERT TO authenticated
  WITH CHECK (personal_id = auth.uid() OR es_admin());

CREATE POLICY "fichajes_update" ON fichajes FOR UPDATE TO authenticated
  USING (es_admin());

CREATE POLICY "fichajes_delete" ON fichajes FOR DELETE TO authenticated
  USING (es_admin());

-- ── TABLA: validaciones ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS validaciones (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  personal_id      UUID NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
  fecha            DATE NOT NULL,
  horas_trabajadas NUMERIC(5,2),
  horas_extra      NUMERIC(5,2) DEFAULT 0,
  validado         BOOLEAN NOT NULL DEFAULT false,
  validado_por     UUID REFERENCES perfiles(id),
  validado_en      TIMESTAMPTZ,
  nota             TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (personal_id, fecha)
);

ALTER TABLE validaciones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "validaciones_admin" ON validaciones FOR ALL TO authenticated
  USING (es_admin()) WITH CHECK (es_admin());

CREATE POLICY "validaciones_read_propio" ON validaciones FOR SELECT TO authenticated
  USING (personal_id = auth.uid() OR es_admin());

-- ============================================================
-- CONFIGURACIÓN MANUAL REQUERIDA EN SUPABASE DASHBOARD
-- ============================================================
-- 1. Storage → New bucket → nombre: "fotos-personal" → Public: ON
--
-- 2. Authentication → Email → "Enable email confirmations" → OFF
--    (necesario para que el admin pueda crear usuarios sin confirmación)
--
-- 3. Crear el primer admin:
--    a) Authentication → Users → Add user → ingresá email + password
--    b) Copiar el UUID del usuario creado
--    c) Ejecutar en SQL Editor:
--       INSERT INTO perfiles (id, nombre, apellido, rol)
--       VALUES ('<UUID>', 'Tu Nombre', 'Tu Apellido', 'admin');
-- ============================================================
