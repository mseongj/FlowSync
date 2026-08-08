-- ============================================================
-- Story 2.1: Teenager Privacy Controls
--
-- Enforces teen privacy at the database level:
--   - PUBLIC events: visible to all family members
--   - PRIVATE events: row visible to family (for "Busy" slots),
--     but content (title/description/location) masked for non-creators
--   - SECRET events: visible ONLY to the creator
-- ============================================================

-- ============================================================
-- Part A: calendar_events table (used by Flutter app)
-- ============================================================

-- Create table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.calendar_events (
  id          TEXT PRIMARY KEY,
  family_id   TEXT,
  creator_id  TEXT,
  title       TEXT NOT NULL,
  description TEXT DEFAULT '',
  location    TEXT DEFAULT '',
  start_time  TIMESTAMPTZ NOT NULL,
  end_time    TIMESTAMPTZ NOT NULL,
  visibility  TEXT NOT NULL DEFAULT 'public',  -- 'public', 'private', 'secret'
  is_offline_created BOOLEAN DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;

-- Policy 1: PUBLIC events — visible to all family members
CREATE POLICY "cal_public_events_family_visible"
  ON public.calendar_events FOR SELECT
  USING (
    visibility = 'public'
    AND (
      creator_id = auth.uid()::text
      OR family_id IN (
        SELECT family_id::text FROM public.family_members WHERE user_id = auth.uid()
      )
    )
  );

-- Policy 2: PRIVATE events — visible to creator (full) + family (row only, content masked client-side)
CREATE POLICY "cal_private_events_family_visible"
  ON public.calendar_events FOR SELECT
  USING (
    visibility = 'private'
    AND (
      creator_id = auth.uid()::text
      OR family_id IN (
        SELECT family_id::text FROM public.family_members WHERE user_id = auth.uid()
      )
    )
  );

-- Policy 3: SECRET events — visible ONLY to creator
CREATE POLICY "cal_secret_events_creator_only"
  ON public.calendar_events FOR SELECT
  USING (
    visibility = 'secret'
    AND creator_id = auth.uid()::text
  );

-- Policy 4: Users can insert their own events
CREATE POLICY "cal_users_can_insert_own"
  ON public.calendar_events FOR INSERT
  WITH CHECK (creator_id = auth.uid()::text);

-- Policy 5: Users can update their own events
CREATE POLICY "cal_users_can_update_own"
  ON public.calendar_events FOR UPDATE
  USING (creator_id = auth.uid()::text);

-- Policy 6: Users can delete their own events
CREATE POLICY "cal_users_can_delete_own"
  ON public.calendar_events FOR DELETE
  USING (creator_id = auth.uid()::text);

-- ============================================================
-- Part B: Privacy View for calendar_events
-- Server-side content masking for PRIVATE events.
-- Flutter can query this view instead of the raw table.
-- ============================================================

CREATE OR REPLACE VIEW public.calendar_events_privacy_view AS
SELECT
  id,
  family_id,
  creator_id,
  start_time,
  end_time,
  visibility,
  is_offline_created,
  created_at,
  updated_at,
  -- Mask content for PRIVATE events when viewer is not the creator
  CASE
    WHEN visibility = 'private' AND creator_id != auth.uid()::text
    THEN '바쁨'
    ELSE title
  END AS title,
  CASE
    WHEN visibility = 'private' AND creator_id != auth.uid()::text
    THEN ''
    ELSE description
  END AS description,
  CASE
    WHEN visibility = 'private' AND creator_id != auth.uid()::text
    THEN ''
    ELSE location
  END AS location
FROM public.calendar_events;

GRANT SELECT ON public.calendar_events_privacy_view TO authenticated;

-- ============================================================
-- Part C: Ensure display_name column exists on family_members
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'family_members'
      AND column_name = 'display_name'
  ) THEN
    ALTER TABLE public.family_members ADD COLUMN display_name TEXT;
  END IF;
END $$;

-- ============================================================
-- Part D: Enable Realtime for calendar_events
-- Required for Supabase Realtime subscriptions
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.calendar_events;
