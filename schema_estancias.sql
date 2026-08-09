-- ============================================================
-- MADERA LABRADA — Estancias y Clientes
-- Ejecutar DESPUÉS de schema_completo.sql
-- ============================================================

-- ── Clientes ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clientes (
  id               BIGSERIAL PRIMARY KEY,
  dni              TEXT UNIQUE,
  nombres          TEXT NOT NULL,
  apellido_paterno TEXT,
  apellido_materno TEXT,
  telefono         TEXT,
  email            TEXT,
  direccion        TEXT,
  nacionalidad     TEXT DEFAULT 'Peruana',
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Índice para búsqueda rápida por DNI o nombre
CREATE INDEX IF NOT EXISTS idx_clientes_dni    ON clientes (dni);
CREATE INDEX IF NOT EXISTS idx_clientes_nombre ON clientes (nombres, apellido_paterno);

ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clientes_read"  ON clientes FOR SELECT TO authenticated USING (true);
CREATE POLICY "clientes_write" ON clientes FOR ALL    TO authenticated
  USING (es_admin() OR es_area('Recepción'))
  WITH CHECK (es_admin() OR es_area('Recepción'));

-- ── Estancias ─────────────────────────────────────────────────
-- Una estancia = un cliente en una habitación por un período
-- Un cliente puede tener varias estancias simultáneas (varias habitaciones)
CREATE TABLE IF NOT EXISTS estancias (
  id              BIGSERIAL PRIMARY KEY,
  cliente_id      BIGINT NOT NULL REFERENCES clientes(id),
  habitacion_id   INTEGER NOT NULL REFERENCES habitaciones(id),
  check_in        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  check_out       TIMESTAMPTZ,
  noches          INTEGER NOT NULL DEFAULT 1,
  tarifa_noche    NUMERIC(10,2) NOT NULL DEFAULT 0,
  estado          TEXT NOT NULL DEFAULT 'activa'
                    CHECK (estado IN ('activa','completada','cancelada')),
  -- Facturación de esta habitación
  comprobante_tipo TEXT CHECK (comprobante_tipo IN ('boleta','factura','ninguno')),
  comprobante_nro  TEXT,
  facturado        BOOLEAN NOT NULL DEFAULT false,
  observacion      TEXT,
  registrado_por   UUID NOT NULL REFERENCES perfiles(id),
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_estancias_cliente    ON estancias (cliente_id);
CREATE INDEX IF NOT EXISTS idx_estancias_habitacion ON estancias (habitacion_id);
CREATE INDEX IF NOT EXISTS idx_estancias_estado     ON estancias (estado);

ALTER TABLE estancias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "estancias_read"  ON estancias FOR SELECT TO authenticated USING (true);
CREATE POLICY "estancias_write" ON estancias FOR ALL    TO authenticated
  USING (es_admin() OR es_area('Recepción'))
  WITH CHECK (es_admin() OR es_area('Recepción'));

-- ── Extras por cliente ────────────────────────────────────────
-- Consumos adicionales (cocina, bazar, servicios) cargados al cliente
-- Cocina y bazar pueden agregar extras directamente desde sus paneles
CREATE TABLE IF NOT EXISTS estancia_extras (
  id             BIGSERIAL PRIMARY KEY,
  cliente_id     BIGINT NOT NULL REFERENCES clientes(id),
  estancia_id    BIGINT REFERENCES estancias(id),   -- NULL = cargo general al cliente
  tipo           TEXT NOT NULL CHECK (tipo IN ('producto','servicio','otro')),
  descripcion    TEXT NOT NULL,
  cantidad       INTEGER NOT NULL DEFAULT 1,
  precio_unit    NUMERIC(10,2) NOT NULL,
  area           TEXT,        -- 'Cocina', 'Bazar', 'Recepción'
  facturado      BOOLEAN NOT NULL DEFAULT false,
  registrado_por UUID NOT NULL REFERENCES perfiles(id),
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_extras_cliente ON estancia_extras (cliente_id);

ALTER TABLE estancia_extras ENABLE ROW LEVEL SECURITY;

-- Todos pueden agregar extras (cocina y bazar también)
CREATE POLICY "extras_read" ON estancia_extras FOR SELECT TO authenticated USING (true);
CREATE POLICY "extras_insert" ON estancia_extras FOR INSERT TO authenticated
  WITH CHECK (registrado_por = auth.uid());
-- Solo recepción y admin pueden editar/eliminar
CREATE POLICY "extras_update_delete" ON estancia_extras FOR ALL TO authenticated
  USING (es_admin() OR es_area('Recepción'));

-- ── Trigger: al hacer check-out, marcar habitación como Limpieza ──
CREATE OR REPLACE FUNCTION fn_checkout_habitacion()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  BEGIN
    IF NEW.estado = 'completada' AND OLD.estado = 'activa' THEN
      UPDATE habitaciones SET estado = 'Limpieza' WHERE id = NEW.habitacion_id;
    END IF;
    RETURN NEW;
  END;
$$;

CREATE TRIGGER trg_checkout_habitacion
  AFTER UPDATE ON estancias
  FOR EACH ROW EXECUTE FUNCTION fn_checkout_habitacion();

-- ── Vista: clientes activos con sus habitaciones ──────────────
CREATE OR REPLACE VIEW clientes_activos AS
SELECT
  c.id                                                      AS cliente_id,
  c.dni,
  c.nombres || ' ' || COALESCE(c.apellido_paterno,'') ||
    CASE WHEN c.apellido_materno IS NOT NULL THEN ' ' || c.apellido_materno ELSE '' END
                                                            AS nombre_completo,
  c.telefono,
  c.nacionalidad,
  COUNT(e.id)                                               AS cant_habitaciones,
  STRING_AGG(h.nombre, ', ' ORDER BY h.nombre)             AS habitaciones,
  STRING_AGG(h.tipo,   ', ' ORDER BY h.nombre)             AS tipos,
  MIN(e.check_in)                                           AS check_in,
  SUM(e.noches * e.tarifa_noche)                            AS total_habitaciones,
  COALESCE(SUM(ex.cantidad * ex.precio_unit) FILTER (WHERE ex.facturado = false), 0)
                                                            AS total_extras_pendientes,
  SUM(e.noches * e.tarifa_noche) +
    COALESCE(SUM(ex.cantidad * ex.precio_unit) FILTER (WHERE ex.facturado = false), 0)
                                                            AS total_general
FROM clientes c
JOIN estancias e      ON e.cliente_id = c.id AND e.estado = 'activa'
JOIN habitaciones h   ON h.id = e.habitacion_id
LEFT JOIN estancia_extras ex ON ex.cliente_id = c.id AND ex.facturado = false
GROUP BY c.id, c.dni, c.nombres, c.apellido_paterno, c.apellido_materno, c.telefono, c.nacionalidad
ORDER BY MIN(e.check_in);
