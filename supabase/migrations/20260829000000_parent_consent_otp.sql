-- ============================================================
-- Migration: Parent Consent OTP Storage
--
-- Stores hashed OTPs for parental consent verification.
-- OTPs expire after 10 minutes and are single-use.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.parent_consent_otps (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  phone       TEXT NOT NULL,
  otp_hash    TEXT NOT NULL,         -- SHA-256 hash of the OTP (never store plaintext)
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '10 minutes'),
  verified_at TIMESTAMPTZ,           -- NULL = not yet verified
  attempts    INT NOT NULL DEFAULT 0, -- brute-force counter
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.parent_consent_otps ENABLE ROW LEVEL SECURITY;

-- No direct access — only via Edge Functions using service_role
CREATE POLICY "deny_direct_access_otp"
  ON public.parent_consent_otps FOR ALL
  USING (false);

-- Cleanup: delete expired OTPs older than 1 hour (if pg_cron is available)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('cleanup-expired-otps', '0 * * * *', $$
      DELETE FROM public.parent_consent_otps
      WHERE expires_at < NOW() - INTERVAL '1 hour';
    $$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not available — safe to ignore
  NULL;
END $$;
