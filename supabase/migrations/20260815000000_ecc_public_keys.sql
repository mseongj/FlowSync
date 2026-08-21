-- ============================================================
-- E2EE Phase 2: ECC Public Keys + GMK Wrapping
-- ============================================================

-- 1. family_ecc_public_keys: stores each member's ECC P-256 public key
CREATE TABLE IF NOT EXISTS public.family_ecc_public_keys (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id   UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  public_key  TEXT NOT NULL,  -- base64 encoded uncompressed ECC P-256 point
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE (family_id, user_id)
);

-- Enable RLS
ALTER TABLE public.family_ecc_public_keys ENABLE ROW LEVEL SECURITY;

-- Grant CRUD to authenticated users (RLS controls row visibility)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.family_ecc_public_keys TO authenticated;

-- Same-family members can read each other's public keys
CREATE POLICY "members_can_read_family_keys"
  ON public.family_ecc_public_keys FOR SELECT
  USING (family_id IN (SELECT get_user_families()));

-- Users can only insert their own public key
CREATE POLICY "users_can_insert_own_key"
  ON public.family_ecc_public_keys FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Users can update their own public key (key rotation)
CREATE POLICY "users_can_update_own_key"
  ON public.family_ecc_public_keys FOR UPDATE
  USING (user_id = auth.uid());

-- 2. Add wrapped_gmk column to family_key_store
-- This stores the GMK encrypted with ECDH shared secret per member
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'family_key_store'
      AND column_name = 'wrapped_gmk'
  ) THEN
    ALTER TABLE public.family_key_store ADD COLUMN wrapped_gmk TEXT;
  END IF;
END $$;

-- 3. Grant access to family_key_store for authenticated role
-- (Edge Function uses service_role, but client needs INSERT/UPDATE)
GRANT INSERT, UPDATE ON public.family_key_store TO authenticated;
