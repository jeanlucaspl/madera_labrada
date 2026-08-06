-- ============================================================
-- MADERA LABRADA — Limpieza de base de datos (rothbard web)
-- Borra todas las tablas y funciones anteriores (tacnet + rothbard)
-- Ejecutar ANTES de supabase_setup.sql
-- ============================================================

-- ── Tablas (CASCADE borra también políticas, índices y foreign keys) ──
DROP TABLE IF EXISTS asistencias          CASCADE;
DROP TABLE IF EXISTS alumnos              CASCADE;
DROP TABLE IF EXISTS profesores           CASCADE;
DROP TABLE IF EXISTS perfiles             CASCADE;
DROP TABLE IF EXISTS academias            CASCADE;
DROP TABLE IF EXISTS pagos                CASCADE;
DROP TABLE IF EXISTS horarios             CASCADE;
DROP TABLE IF EXISTS materias             CASCADE;
DROP TABLE IF EXISTS aulas                CASCADE;
DROP TABLE IF EXISTS notificaciones       CASCADE;
DROP TABLE IF EXISTS fcm_tokens           CASCADE;

-- Agrega aquí cualquier otra tabla que pueda existir
-- DROP TABLE IF EXISTS <nombre> CASCADE;

-- ── Funciones ────────────────────────────────────────────────
DROP FUNCTION IF EXISTS es_admin()         CASCADE;
DROP FUNCTION IF EXISTS mi_academia_id()   CASCADE;
DROP FUNCTION IF EXISTS mi_id()            CASCADE;

-- ── Verificar que quedó limpio ───────────────────────────────
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Si la consulta anterior devuelve filas, agregá los DROP TABLE
-- que falten y volvé a ejecutar antes de correr supabase_setup.sql
