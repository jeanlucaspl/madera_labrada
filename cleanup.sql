-- ============================================================
-- LIMPIEZA TOTAL — schema public
-- Borra TODAS las tablas, funciones y secuencias existentes
-- sin necesidad de conocer sus nombres.
-- Ejecutar ANTES de supabase_setup.sql
-- ============================================================

-- 1. Borrar todas las tablas del schema public (con CASCADE)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE 'DROP TABLE IF EXISTS public.' || quote_ident(r.tablename) || ' CASCADE';
  END LOOP;
END $$;

-- 2. Borrar todas las funciones del schema public
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.fn || ' CASCADE';
  END LOOP;
END $$;

-- 3. Verificar — debe devolver 0 filas
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
