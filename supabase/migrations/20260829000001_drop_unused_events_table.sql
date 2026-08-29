-- ============================================================
-- Migration: Drop unused `events` table
--
-- The `events` table was created in core_schema.sql but was
-- superseded by `calendar_events` (teen_privacy_rls.sql).
-- No Dart or TypeScript code references `public.events`.
--
-- This migration removes:
--   - The `events` table and all its RLS policies
--   - The `set_timestamp_events` trigger
--   - The `hard-delete-tombstones` cron job
--   - The `privacy_level` ENUM type (replaced by TEXT in calendar_events)
-- ============================================================

-- 1. Unschedule the tombstone cron job (if pg_cron is available)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    PERFORM cron.unschedule('hard-delete-tombstones');
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not available or job doesn't exist — safe to ignore
  NULL;
END $$;

-- 2. Drop the table (CASCADE removes triggers, policies, indexes)
DROP TABLE IF EXISTS public.events CASCADE;

-- 3. Drop the unused privacy_level ENUM
-- (calendar_events uses TEXT for visibility instead)
DROP TYPE IF EXISTS privacy_level;
