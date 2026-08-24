-- ============================================================
-- Migration: Add UNIQUE constraint to family_key_store
--
-- Problem: family_key_exchange_service.dart calls
--   .upsert({...}, onConflict: 'family_id, member_id')
-- but there was no UNIQUE constraint on (family_id, member_id).
-- Without it, upsert behaves as INSERT, creating duplicate rows.
-- ============================================================

-- Add UNIQUE constraint (idempotent — skips if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_family_key_store_member'
  ) THEN
    ALTER TABLE public.family_key_store
      ADD CONSTRAINT uq_family_key_store_member
      UNIQUE (family_id, member_id);
  END IF;
END $$;
