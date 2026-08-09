-- ============================================================
-- MADERA LABRADA — Base de datos Supabase
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- Idempotente: se puede correr múltiples veces sin error
-- ============================================================

-- ── TABLA: perfiles ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perfiles (
  id              UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  nombre          TEXT NOT NULL,
  apellido        TEXT NOT NULL,
  dni             TEXT,
  rol             TEXT NOT NULL DEFAULT 'empleado' CHECK (rol IN ('superadmin','admin','empleado')),
  turno           TEXT CHECK (turno IN ('mañana','tarde','noche')),
  area            TEXT CHECK (area IN ('Cocina','Limpieza','Recepción','Inventario','RRHH') OR area IS NULL),
  foto_url        TEXT,
  foto_descriptor JSONB,
  activo          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION es_admin()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid() AND rol IN ('superadmin','admin') AND activo = true
    );
  END;
$$;

CREATE OR REPLACE FUNCTION es_superadmin()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid() AND rol = 'superadmin' AND activo = true
    );
  END;
$$;

ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "perfiles_read"   ON perfiles;
DROP POLICY IF EXISTS "perfiles_insert" ON perfiles;
DROP POLICY IF EXISTS "perfiles_update" ON perfiles;
DROP POLICY IF EXISTS "perfiles_delete" ON perfiles;

CREATE POLICY "perfiles_read" ON perfiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR es_admin());

CREATE POLICY "perfiles_insert" ON perfiles FOR INSERT TO authenticated
  WITH CHECK (es_admin());

CREATE POLICY "perfiles_update" ON perfiles FOR UPDATE TO authenticated
  USING (id = auth.uid() OR es_admin());

CREATE POLICY "perfiles_delete" ON perfiles FOR DELETE TO authenticated
  USING (es_superadmin());

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

DROP POLICY IF EXISTS "fichajes_read"   ON fichajes;
DROP POLICY IF EXISTS "fichajes_insert" ON fichajes;
DROP POLICY IF EXISTS "fichajes_update" ON fichajes;
DROP POLICY IF EXISTS "fichajes_delete" ON fichajes;

CREATE POLICY "fichajes_read" ON fichajes FOR SELECT TO authenticated
  USING (personal_id = auth.uid() OR es_admin());

CREATE POLICY "fichajes_insert" ON fichajes FOR INSERT TO authenticated
  WITH CHECK (personal_id = auth.uid() OR es_admin());

CREATE POLICY "fichajes_update" ON fichajes FOR UPDATE TO authenticated
  USING (es_admin());

CREATE POLICY "fichajes_delete" ON fichajes FOR DELETE TO authenticated
  USING (es_superadmin());

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

DROP POLICY IF EXISTS "validaciones_admin"       ON validaciones;
DROP POLICY IF EXISTS "validaciones_read_propio" ON validaciones;
DROP POLICY IF EXISTS "validaciones_read"        ON validaciones;
DROP POLICY IF EXISTS "validaciones_write"       ON validaciones;

CREATE POLICY "validaciones_read" ON validaciones FOR SELECT TO authenticated
  USING (personal_id = auth.uid() OR es_admin());

CREATE POLICY "validaciones_write" ON validaciones FOR ALL TO authenticated
  USING (es_admin()) WITH CHECK (es_admin());

-- ============================================================
-- CONFIGURACIÓN MANUAL REQUERIDA EN SUPABASE DASHBOARD
-- ============================================================
-- 1. Storage → New bucket → nombre: "fotos-personal" → Public: ON
--
-- 2. Authentication → Email → "Enable email confirmations" → OFF
--
-- 3. Asignar superadmin (reemplazar con tu UUID real):
--    UPDATE perfiles SET rol = 'superadmin', area = NULL
--    WHERE id = '<TU_UUID>';
--
-- 4. Crear admins por área:
--    UPDATE perfiles SET rol = 'admin', area = 'RRHH'
--    WHERE id = '<UUID_DEL_ADMIN>';
-- ============================================================
