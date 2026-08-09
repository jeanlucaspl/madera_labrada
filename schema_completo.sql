-- ============================================================
-- MADERA LABRADA — Schema Completo v2
-- Ejecutar DESPUÉS de supabase_setup.sql
-- ============================================================
-- ORDEN DE EJECUCIÓN:
--   1. supabase_setup.sql  (perfiles, fichajes, validaciones)
--   2. este archivo
--   3. seed_data.sql       (productos, habitaciones)
-- ============================================================

-- ============================================================
-- PASO 1: ACTUALIZAR TABLA PERFILES (ya existe)
-- Ampliar roles y agregar campos faltantes
-- ============================================================

-- Actualizar constraint de rol para incluir superadmin y admins por área
ALTER TABLE perfiles
  DROP CONSTRAINT IF EXISTS perfiles_rol_check;

ALTER TABLE perfiles
  ADD CONSTRAINT perfiles_rol_check
  CHECK (rol IN ('superadmin','admin','empleado'));

-- Actualizar constraint de área para incluir todos los sectores
ALTER TABLE perfiles
  DROP CONSTRAINT IF EXISTS perfiles_area_check;

ALTER TABLE perfiles
  ADD CONSTRAINT perfiles_area_check
  CHECK (area IN ('Cocina','Limpieza','Recepción','Inventario','RRHH') OR area IS NULL);

-- Marcar al superadmin (ya existe en auth.users y en perfiles)
-- REEMPLAZAR <TU_UUID> con el UUID real del usuario en Supabase Auth
-- Dashboard → Authentication → Users → copiar el UUID
-- UPDATE perfiles SET rol = 'superadmin', area = NULL WHERE id = '<TU_UUID>';

-- ============================================================
-- PASO 2: ACTUALIZAR Y CREAR FUNCIONES HELPER
-- ============================================================

-- es_superadmin(): solo el superadmin
CREATE OR REPLACE FUNCTION es_superadmin()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid() AND rol = 'superadmin' AND activo = true
    );
  END;
$$;

-- es_admin(): superadmin O admin de cualquier área
CREATE OR REPLACE FUNCTION es_admin()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid() AND rol IN ('superadmin','admin') AND activo = true
    );
  END;
$$;

-- es_admin_area(area): superadmin O admin de esa área específica
CREATE OR REPLACE FUNCTION es_admin_area(area_check TEXT)
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid()
        AND activo = true
        AND (
          rol = 'superadmin'
          OR (rol = 'admin' AND area = area_check)
        )
    );
  END;
$$;

-- mi_rol(): devuelve el rol del usuario actual
CREATE OR REPLACE FUNCTION mi_rol()
  RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN (SELECT rol FROM perfiles WHERE id = auth.uid() AND activo = true);
  END;
$$;

-- mi_area(): devuelve el área del usuario actual
CREATE OR REPLACE FUNCTION mi_area()
  RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN (SELECT area FROM perfiles WHERE id = auth.uid() AND activo = true);
  END;
$$;

-- mis_categorias_inventario(): categorías que puede gestionar el usuario
--   Superadmin / Admin Inventario → todas
--   Admin/empleado Cocina         → COCINA, BEBIDAS, BAR
--   Admin/empleado Recepción      → BAZAR, GOLOSINAS
--   Admin/empleado Limpieza       → BAZAR (solo consulta de lo que usan)
--   RRHH                          → ninguna
CREATE OR REPLACE FUNCTION mis_categorias_inventario()
  RETURNS TEXT[] LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  DECLARE
    v_rol  TEXT;
    v_area TEXT;
  BEGIN
    SELECT rol, area INTO v_rol, v_area
      FROM perfiles WHERE id = auth.uid() AND activo = true;

    IF v_rol = 'superadmin' OR v_area = 'Inventario' THEN
      RETURN ARRAY['COCINA','BEBIDAS','BAR','BAZAR','GOLOSINAS'];
    END IF;

    RETURN CASE v_area
      WHEN 'Cocina'    THEN ARRAY['COCINA','BEBIDAS','BAR']
      WHEN 'Recepción' THEN ARRAY['BAZAR','GOLOSINAS']
      WHEN 'Limpieza'  THEN ARRAY['BAZAR']
      ELSE ARRAY[]::TEXT[]
    END;
  END;
$$;

-- puede_gestionar_habitaciones(): Recepción, Limpieza, superadmin
CREATE OR REPLACE FUNCTION puede_gestionar_habitaciones()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid()
        AND activo = true
        AND (
          rol = 'superadmin'
          OR (rol IN ('admin','empleado') AND area IN ('Recepción','Limpieza'))
        )
    );
  END;
$$;

-- puede_gestionar_caja(): Recepción, Cocina (solo sus ingresos), superadmin
CREATE OR REPLACE FUNCTION puede_gestionar_caja()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid()
        AND activo = true
        AND (
          rol = 'superadmin'
          OR (rol IN ('admin','empleado') AND area IN ('Recepción','Cocina'))
        )
    );
  END;
$$;

-- puede_gestionar_personal(): RRHH y superadmin
CREATE OR REPLACE FUNCTION puede_gestionar_personal()
  RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM perfiles
      WHERE id = auth.uid()
        AND activo = true
        AND (rol = 'superadmin' OR (rol = 'admin' AND area = 'RRHH'))
    );
  END;
$$;

-- ============================================================
-- PASO 3: ACTUALIZAR RLS DE TABLAS EXISTENTES
-- ============================================================

-- perfiles: RRHH puede ver/gestionar todo el personal
DROP POLICY IF EXISTS "perfiles_read"   ON perfiles;
DROP POLICY IF EXISTS "perfiles_insert" ON perfiles;
DROP POLICY IF EXISTS "perfiles_update" ON perfiles;
DROP POLICY IF EXISTS "perfiles_delete" ON perfiles;

CREATE POLICY "perfiles_read" ON perfiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR es_admin());

CREATE POLICY "perfiles_insert" ON perfiles FOR INSERT TO authenticated
  WITH CHECK (puede_gestionar_personal());

CREATE POLICY "perfiles_update" ON perfiles FOR UPDATE TO authenticated
  USING (
    id = auth.uid()           -- cada uno puede editar su propio perfil
    OR puede_gestionar_personal()
  );

CREATE POLICY "perfiles_delete" ON perfiles FOR DELETE TO authenticated
  USING (es_superadmin());   -- solo superadmin puede eliminar perfiles

-- fichajes: RRHH y superadmin tienen acceso total; empleados solo el suyo
DROP POLICY IF EXISTS "fichajes_read"   ON fichajes;
DROP POLICY IF EXISTS "fichajes_insert" ON fichajes;
DROP POLICY IF EXISTS "fichajes_update" ON fichajes;
DROP POLICY IF EXISTS "fichajes_delete" ON fichajes;

CREATE POLICY "fichajes_read" ON fichajes FOR SELECT TO authenticated
  USING (personal_id = auth.uid() OR puede_gestionar_personal());

CREATE POLICY "fichajes_insert" ON fichajes FOR INSERT TO authenticated
  WITH CHECK (personal_id = auth.uid() OR puede_gestionar_personal());

CREATE POLICY "fichajes_update" ON fichajes FOR UPDATE TO authenticated
  USING (puede_gestionar_personal());

CREATE POLICY "fichajes_delete" ON fichajes FOR DELETE TO authenticated
  USING (es_superadmin());

-- validaciones: solo RRHH y superadmin validan
DROP POLICY IF EXISTS "validaciones_admin"       ON validaciones;
DROP POLICY IF EXISTS "validaciones_read_propio" ON validaciones;
DROP POLICY IF EXISTS "validaciones_read"        ON validaciones;
DROP POLICY IF EXISTS "validaciones_write"       ON validaciones;

CREATE POLICY "validaciones_read" ON validaciones FOR SELECT TO authenticated
  USING (personal_id = auth.uid() OR puede_gestionar_personal());

CREATE POLICY "validaciones_write" ON validaciones FOR ALL TO authenticated
  USING (puede_gestionar_personal()) WITH CHECK (puede_gestionar_personal());

-- ============================================================
-- PASO 4: CATÁLOGOS
-- ============================================================

-- ── Categorías de producto ────────────────────────────────────
CREATE TABLE IF NOT EXISTS categorias_producto (
  id     SERIAL PRIMARY KEY,
  nombre TEXT UNIQUE NOT NULL,
  area   TEXT  -- área responsable
);

INSERT INTO categorias_producto (nombre, area) VALUES
  ('COCINA',    'Cocina'),
  ('BEBIDAS',   'Cocina'),
  ('BAR',       'Cocina'),
  ('BAZAR',     'Recepción'),
  ('GOLOSINAS', 'Recepción')
ON CONFLICT (nombre) DO UPDATE SET area = EXCLUDED.area;

ALTER TABLE categorias_producto ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cat_prod_read" ON categorias_producto FOR SELECT TO authenticated USING (true);
CREATE POLICY "cat_prod_write" ON categorias_producto FOR ALL TO authenticated
  USING (es_admin_area('Inventario') OR es_superadmin())
  WITH CHECK (es_admin_area('Inventario') OR es_superadmin());

-- ── Tipos de habitación ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS tipos_habitacion (
  id         SERIAL PRIMARY KEY,
  nombre     TEXT UNIQUE NOT NULL,
  tiene_aire BOOLEAN DEFAULT FALSE,
  capacidad  INTEGER DEFAULT 2
);

INSERT INTO tipos_habitacion (nombre, tiene_aire, capacidad) VALUES
  ('Simple',            FALSE, 1),
  ('Doble',             FALSE, 2),
  ('Triple',            FALSE, 3),
  ('Cuádruple',         FALSE, 4),
  ('Quíntuple',         FALSE, 5),
  ('Simple C/ Aire',    TRUE,  1),
  ('Doble C/ Aire',     TRUE,  2),
  ('Triple C/ Aire',    TRUE,  3),
  ('Cuádruple C/ Aire', TRUE,  4),
  ('Quíntuple C/ Aire', TRUE,  5)
ON CONFLICT (nombre) DO NOTHING;

ALTER TABLE tipos_habitacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tipos_hab_read" ON tipos_habitacion FOR SELECT TO authenticated USING (true);
CREATE POLICY "tipos_hab_write" ON tipos_habitacion FOR ALL TO authenticated
  USING (es_superadmin()) WITH CHECK (es_superadmin());

-- ── Habitaciones físicas ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS habitaciones (
  id     SERIAL PRIMARY KEY,
  nombre TEXT UNIQUE NOT NULL,
  tipo   TEXT REFERENCES tipos_habitacion(nombre),
  bloque TEXT,
  estado TEXT NOT NULL DEFAULT 'Disponible'
           CHECK (estado IN ('Disponible','Ocupado','Limpieza','Mantenimiento')),
  activo BOOLEAN NOT NULL DEFAULT true
);

ALTER TABLE habitaciones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hab_read" ON habitaciones FOR SELECT TO authenticated USING (true);

CREATE POLICY "hab_update" ON habitaciones FOR UPDATE TO authenticated
  USING (puede_gestionar_habitaciones());

CREATE POLICY "hab_insert_delete" ON habitaciones FOR ALL TO authenticated
  USING (es_superadmin()) WITH CHECK (es_superadmin());

-- ── Log de cambios de estado de habitaciones ──────────────────
CREATE TABLE IF NOT EXISTS habitaciones_log (
  id              BIGSERIAL PRIMARY KEY,
  habitacion_id   INTEGER NOT NULL REFERENCES habitaciones(id),
  estado_anterior TEXT,
  estado_nuevo    TEXT NOT NULL,
  observacion     TEXT,
  registrado_por  UUID NOT NULL REFERENCES perfiles(id),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE habitaciones_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hab_log_read" ON habitaciones_log FOR SELECT TO authenticated
  USING (es_admin() OR puede_gestionar_habitaciones());

CREATE POLICY "hab_log_insert" ON habitaciones_log FOR INSERT TO authenticated
  WITH CHECK (registrado_por = auth.uid() AND puede_gestionar_habitaciones());

-- Trigger: log automático + notificación al cambiar estado
CREATE OR REPLACE FUNCTION fn_log_estado_habitacion()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  BEGIN
    IF OLD.estado IS DISTINCT FROM NEW.estado THEN
      INSERT INTO habitaciones_log (habitacion_id, estado_anterior, estado_nuevo, registrado_por)
      VALUES (NEW.id, OLD.estado, NEW.estado, auth.uid());

      IF NEW.estado = 'Limpieza' THEN
        INSERT INTO notificaciones (tipo, titulo, mensaje, area_destino, datos)
        VALUES (
          'limpieza_pendiente',
          'Limpiar: ' || NEW.nombre,
          'La habitación ' || NEW.nombre || ' necesita limpieza',
          'Limpieza',
          jsonb_build_object('habitacion_id', NEW.id, 'habitacion', NEW.nombre, 'tipo', NEW.tipo)
        );
      END IF;

      IF NEW.estado = 'Disponible' AND OLD.estado = 'Limpieza' THEN
        INSERT INTO notificaciones (tipo, titulo, mensaje, area_destino, datos)
        VALUES (
          'habitacion_lista',
          'Lista: ' || NEW.nombre,
          'La habitación ' || NEW.nombre || ' está disponible',
          'Recepción',
          jsonb_build_object('habitacion_id', NEW.id, 'habitacion', NEW.nombre, 'tipo', NEW.tipo)
        );
      END IF;
    END IF;
    RETURN NEW;
  END;
$$;

CREATE TRIGGER trg_log_estado_habitacion
  AFTER UPDATE ON habitaciones
  FOR EACH ROW EXECUTE FUNCTION fn_log_estado_habitacion();

-- ============================================================
-- PASO 5: INVENTARIO
-- ============================================================

CREATE TABLE IF NOT EXISTS productos (
  id            SERIAL PRIMARY KEY,
  codigo        TEXT UNIQUE NOT NULL,
  nombre        TEXT NOT NULL,
  categoria     TEXT REFERENCES categorias_producto(nombre),
  precio_compra NUMERIC(10,2) DEFAULT 0,
  precio_venta  NUMERIC(10,2) DEFAULT 0,
  proveedor     TEXT,
  stock_actual  INTEGER NOT NULL DEFAULT 0,
  stock_minimo  INTEGER NOT NULL DEFAULT 5,
  activo        BOOLEAN NOT NULL DEFAULT true,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE productos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "prod_read" ON productos FOR SELECT TO authenticated USING (true);

CREATE POLICY "prod_update" ON productos FOR UPDATE TO authenticated
  USING (
    es_superadmin() OR
    es_admin_area('Inventario') OR
    categoria = ANY(mis_categorias_inventario())
  );

CREATE POLICY "prod_insert_delete" ON productos FOR ALL TO authenticated
  USING (es_superadmin() OR es_admin_area('Inventario'))
  WITH CHECK (es_superadmin() OR es_admin_area('Inventario'));

-- ── Movimientos de inventario (fuente de verdad) ──────────────
CREATE TABLE IF NOT EXISTS movimientos_inventario (
  id            BIGSERIAL PRIMARY KEY,
  producto_id   INTEGER NOT NULL REFERENCES productos(id),
  tipo          TEXT NOT NULL CHECK (tipo IN ('entrada','salida','ajuste','consumo')),
  -- entrada:  compra / reposición
  -- salida:   venta registrada manualmente
  -- ajuste:   corrección por admin (puede ser negativo)
  -- consumo:  uso interno (desayunos, limpieza, etc.)
  cantidad      INTEGER NOT NULL CHECK (cantidad > 0),
  stock_antes   INTEGER NOT NULL DEFAULT 0,  -- llenado por trigger
  stock_despues INTEGER NOT NULL DEFAULT 0,  -- llenado por trigger
  motivo        TEXT,
  area          TEXT NOT NULL,
  registrado_por UUID NOT NULL REFERENCES perfiles(id),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE movimientos_inventario ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mov_inv_read" ON movimientos_inventario FOR SELECT TO authenticated
  USING (
    es_superadmin() OR
    es_admin_area('Inventario') OR
    EXISTS (
      SELECT 1 FROM productos p
      WHERE p.id = producto_id
        AND p.categoria = ANY(mis_categorias_inventario())
    )
  );

CREATE POLICY "mov_inv_insert" ON movimientos_inventario FOR INSERT TO authenticated
  WITH CHECK (
    registrado_por = auth.uid() AND (
      es_superadmin() OR
      es_admin_area('Inventario') OR
      EXISTS (
        SELECT 1 FROM productos p
        WHERE p.id = producto_id
          AND p.categoria = ANY(mis_categorias_inventario())
      )
    )
  );

-- Movimientos son inmutables: no UPDATE ni DELETE
-- Los ajustes se registran como una nueva fila tipo 'ajuste'

-- Trigger: actualizar stock_actual en productos
CREATE OR REPLACE FUNCTION fn_actualizar_stock()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  DECLARE
    v_stock_antes   INTEGER;
    v_delta         INTEGER;
    v_stock_despues INTEGER;
  BEGIN
    SELECT stock_actual INTO v_stock_antes FROM productos WHERE id = NEW.producto_id;

    v_delta := CASE NEW.tipo
      WHEN 'entrada' THEN  NEW.cantidad
      WHEN 'ajuste'  THEN  NEW.cantidad
      WHEN 'salida'  THEN -NEW.cantidad
      WHEN 'consumo' THEN -NEW.cantidad
    END;

    v_stock_despues := v_stock_antes + v_delta;

    -- Guardar en la misma fila para el historial
    NEW.stock_antes   := v_stock_antes;
    NEW.stock_despues := v_stock_despues;

    UPDATE productos
      SET stock_actual = v_stock_despues, updated_at = NOW()
      WHERE id = NEW.producto_id;

    RETURN NEW;
  END;
$$;

CREATE TRIGGER trg_actualizar_stock
  BEFORE INSERT ON movimientos_inventario
  FOR EACH ROW EXECUTE FUNCTION fn_actualizar_stock();

-- Trigger: notificar stock bajo después de cada movimiento
CREATE OR REPLACE FUNCTION fn_notificar_stock_bajo()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  DECLARE
    v_prod   productos%ROWTYPE;
    v_area   TEXT;
  BEGIN
    SELECT * INTO v_prod FROM productos WHERE id = NEW.producto_id;
    SELECT area INTO v_area FROM categorias_producto WHERE nombre = v_prod.categoria;

    IF v_prod.stock_actual <= v_prod.stock_minimo THEN
      INSERT INTO notificaciones (tipo, titulo, mensaje, area_destino, datos)
      VALUES (
        'stock_bajo',
        'Stock bajo: ' || v_prod.nombre,
        'Quedan ' || v_prod.stock_actual || ' unidades (mínimo ' || v_prod.stock_minimo || ')',
        v_area,
        jsonb_build_object(
          'producto_id', v_prod.id,
          'codigo',      v_prod.codigo,
          'stock',       v_prod.stock_actual,
          'minimo',      v_prod.stock_minimo
        )
      );
    END IF;
    RETURN NEW;
  END;
$$;

CREATE TRIGGER trg_notificar_stock_bajo
  AFTER INSERT ON movimientos_inventario
  FOR EACH ROW EXECUTE FUNCTION fn_notificar_stock_bajo();

-- ============================================================
-- PASO 6: CAJA
-- ============================================================

-- Una sesión de caja por turno por día
CREATE TABLE IF NOT EXISTS caja_sesiones (
  id             BIGSERIAL PRIMARY KEY,
  fecha          DATE NOT NULL DEFAULT CURRENT_DATE,
  turno          TEXT NOT NULL CHECK (turno IN ('mañana','tarde','noche')),
  monto_apertura NUMERIC(10,2) NOT NULL DEFAULT 0,
  monto_cierre   NUMERIC(10,2),
  diferencia     NUMERIC(10,2),   -- monto_cierre - saldo_esperado
  abierto_por    UUID NOT NULL REFERENCES perfiles(id),
  cerrado_por    UUID REFERENCES perfiles(id),
  abierto_en     TIMESTAMPTZ DEFAULT NOW(),
  cerrado_en     TIMESTAMPTZ,
  estado         TEXT NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta','cerrada')),
  observacion    TEXT,
  UNIQUE (fecha, turno)
);

ALTER TABLE caja_sesiones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "caja_ses_read" ON caja_sesiones FOR SELECT TO authenticated
  USING (es_admin() OR puede_gestionar_caja());

CREATE POLICY "caja_ses_insert" ON caja_sesiones FOR INSERT TO authenticated
  WITH CHECK (es_admin_area('Recepción') OR es_superadmin());

CREATE POLICY "caja_ses_update" ON caja_sesiones FOR UPDATE TO authenticated
  USING (es_admin_area('Recepción') OR es_superadmin());

-- ── Movimientos de caja ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS caja_movimientos (
  id               BIGSERIAL PRIMARY KEY,
  sesion_id        BIGINT REFERENCES caja_sesiones(id),
  tipo             TEXT NOT NULL CHECK (tipo IN ('ingreso','egreso')),
  categoria        TEXT NOT NULL,
  -- INGRESOS:  'habitacion' | 'restaurant' | 'bar' | 'bazar' | 'servicio' | 'otro'
  -- EGRESOS:   'compras' | 'servicios' | 'mantenimiento' | 'pago_personal' | 'otro'
  concepto         TEXT NOT NULL,
  monto            NUMERIC(10,2) NOT NULL CHECK (monto > 0),
  metodo_pago      TEXT CHECK (metodo_pago IN ('efectivo','yape','pos','transferencia','credito')),
  area             TEXT NOT NULL,
  referencia       TEXT,       -- número de habitación, nro de pedido, etc.
  registrado_por   UUID NOT NULL REFERENCES perfiles(id),
  anulado          BOOLEAN NOT NULL DEFAULT false,
  anulado_por      UUID REFERENCES perfiles(id),
  anulado_en       TIMESTAMPTZ,
  motivo_anulacion TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE caja_movimientos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "caja_mov_read" ON caja_movimientos FOR SELECT TO authenticated
  USING (
    es_superadmin() OR
    es_admin_area('Recepción') OR
    area = mi_area()
  );

-- Cocina solo registra ingresos de restaurant/bar
-- Recepción registra todo
-- Superadmin registra todo
CREATE POLICY "caja_mov_insert" ON caja_movimientos FOR INSERT TO authenticated
  WITH CHECK (
    registrado_por = auth.uid() AND (
      es_superadmin() OR
      es_admin_area('Recepción') OR
      (
        mi_area() = 'Cocina' AND
        tipo = 'ingreso' AND
        categoria IN ('restaurant','bar')
      )
    )
  );

-- Solo admin Recepción y superadmin pueden anular
CREATE POLICY "caja_mov_update" ON caja_movimientos FOR UPDATE TO authenticated
  USING (es_admin_area('Recepción') OR es_superadmin());

-- Trigger: notificar egresos grandes al superadmin
CREATE OR REPLACE FUNCTION fn_notificar_caja()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  BEGIN
    IF NEW.tipo = 'egreso' AND NEW.monto > 100 THEN
      INSERT INTO notificaciones (tipo, titulo, mensaje, area_destino, datos)
      VALUES (
        'egreso_alto',
        'Egreso S/ ' || NEW.monto,
        NEW.concepto || ' — ' || NEW.area,
        NULL,  -- NULL = solo superadmin lo ve
        jsonb_build_object('movimiento_id', NEW.id, 'monto', NEW.monto, 'area', NEW.area)
      );
    END IF;
    RETURN NEW;
  END;
$$;

CREATE TRIGGER trg_notificar_caja
  AFTER INSERT ON caja_movimientos
  FOR EACH ROW EXECUTE FUNCTION fn_notificar_caja();

-- ============================================================
-- PASO 7: NOTIFICACIONES
-- ============================================================

CREATE TABLE IF NOT EXISTS notificaciones (
  id              BIGSERIAL PRIMARY KEY,
  tipo            TEXT NOT NULL,
  -- 'stock_bajo' | 'habitacion_lista' | 'limpieza_pendiente'
  -- 'egreso_alto' | 'manual'
  titulo          TEXT NOT NULL,
  mensaje         TEXT,
  area_destino    TEXT,    -- área que ve la notif; NULL = solo superadmin
  perfil_destino  UUID REFERENCES perfiles(id),  -- usuario específico; NULL = broadcast al área
  leida           BOOLEAN NOT NULL DEFAULT false,
  datos           JSONB,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE notificaciones ENABLE ROW LEVEL SECURITY;

-- Superadmin ve todas
-- Cada área ve las suyas
-- Cada usuario ve las dirigidas a él
CREATE POLICY "notif_read" ON notificaciones FOR SELECT TO authenticated
  USING (
    es_superadmin() OR
    (area_destino IS NOT NULL AND area_destino = mi_area()) OR
    perfil_destino = auth.uid()
  );

CREATE POLICY "notif_insert" ON notificaciones FOR INSERT TO authenticated
  WITH CHECK (true);  -- triggers y admins pueden insertar

CREATE POLICY "notif_update" ON notificaciones FOR UPDATE TO authenticated
  USING (
    es_superadmin() OR
    area_destino = mi_area() OR
    perfil_destino = auth.uid()
  );

-- ============================================================
-- PASO 8: VISTAS ÚTILES
-- ============================================================

-- Resumen de caja por sesión
CREATE OR REPLACE VIEW resumen_caja AS
SELECT
  s.id            AS sesion_id,
  s.fecha,
  s.turno,
  s.estado,
  s.monto_apertura,
  COALESCE(SUM(CASE WHEN m.tipo='ingreso' AND NOT m.anulado THEN m.monto END), 0) AS total_ingresos,
  COALESCE(SUM(CASE WHEN m.tipo='egreso'  AND NOT m.anulado THEN m.monto END), 0) AS total_egresos,
  s.monto_apertura
    + COALESCE(SUM(CASE WHEN m.tipo='ingreso' AND NOT m.anulado THEN m.monto END), 0)
    - COALESCE(SUM(CASE WHEN m.tipo='egreso'  AND NOT m.anulado THEN m.monto END), 0)
    AS saldo_esperado,
  (pa.nombre || ' ' || pa.apellido) AS abierto_por,
  (pc.nombre || ' ' || pc.apellido) AS cerrado_por
FROM caja_sesiones s
LEFT JOIN caja_movimientos m ON m.sesion_id = s.id
LEFT JOIN perfiles pa ON pa.id = s.abierto_por
LEFT JOIN perfiles pc ON pc.id = s.cerrado_por
GROUP BY s.id, s.fecha, s.turno, s.estado, s.monto_apertura,
         pa.nombre, pa.apellido, pc.nombre, pc.apellido;

-- Stock con alertas por área
CREATE OR REPLACE VIEW stock_alertas AS
SELECT
  p.id,
  p.codigo,
  p.nombre,
  p.categoria,
  c.area AS area_responsable,
  p.stock_actual,
  p.stock_minimo,
  p.precio_venta,
  CASE
    WHEN p.stock_actual  = 0              THEN 'sin_stock'
    WHEN p.stock_actual <= p.stock_minimo THEN 'stock_bajo'
    ELSE 'ok'
  END AS alerta
FROM productos p
JOIN categorias_producto c ON c.nombre = p.categoria
WHERE p.activo = true
ORDER BY alerta DESC, p.categoria, p.nombre;

-- Asistencia de hoy con estado actual
CREATE OR REPLACE VIEW asistencia_hoy AS
SELECT
  p.id,
  p.nombre || ' ' || p.apellido AS empleado,
  p.area,
  p.turno,
  MIN(CASE WHEN f.tipo='entrada' THEN f.hora END) AS entrada,
  MAX(CASE WHEN f.tipo='salida'  THEN f.hora END) AS salida,
  CASE
    WHEN MIN(CASE WHEN f.tipo='entrada' THEN f.hora END) IS NULL THEN 'ausente'
    WHEN MAX(CASE WHEN f.tipo='salida'  THEN f.hora END) IS NULL THEN 'en_jornada'
    ELSE 'completado'
  END AS estado_jornada
FROM perfiles p
LEFT JOIN fichajes f ON f.personal_id = p.id AND f.fecha = CURRENT_DATE
WHERE p.activo = true AND p.rol = 'empleado'
GROUP BY p.id, p.nombre, p.apellido, p.area, p.turno;

-- ============================================================
-- PASO 9: HABILITAR REALTIME EN SUPABASE DASHBOARD
-- ============================================================
-- Database → Replication → Tables → activar:
--   ✅ notificaciones
--   ✅ habitaciones
--   ✅ caja_movimientos
--   ✅ movimientos_inventario
--
-- Esto permite que la app reciba cambios en tiempo real.
-- En JS:
--   supabase.channel('cambios')
--     .on('postgres_changes',
--         { event: 'INSERT', schema: 'public', table: 'notificaciones' },
--         payload => mostrarToast(payload.new))
--     .subscribe()

-- ============================================================
-- PASO 10: ASIGNAR SUPERADMIN
-- ============================================================
-- Ejecutar esto MANUALMENTE con el UUID real:
--
--   UPDATE perfiles
--     SET rol = 'superadmin', area = NULL
--     WHERE id = '<TU_UUID>';
--
-- Para crear admins por área:
--
--   UPDATE perfiles
--     SET rol = 'admin', area = 'RRHH'         -- o Cocina, Limpieza, etc.
--     WHERE id = '<UUID_DEL_ADMIN>';
-- ============================================================
