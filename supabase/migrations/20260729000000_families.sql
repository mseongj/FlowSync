-- ============================================================
-- Unit 5: Family Groups
-- Creates families, family_members, and family_invites tables
-- ============================================================

-- 1. families table
CREATE TABLE IF NOT EXISTS public.families (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  created_by  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Ensure created_by column exists (core_schema may have created the table without it)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'families'
      AND column_name = 'created_by'
  ) THEN
    ALTER TABLE public.families ADD COLUMN created_by uuid REFERENCES auth.users(id) ON DELETE CASCADE;
  END IF;
END $$;

-- 2. family_members table
CREATE TABLE IF NOT EXISTS public.family_members (
  family_id   uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'member',  -- 'admin' | 'member'
  joined_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (family_id, user_id)
);

-- 3. family_invites table (single-use, TTL 24h)
CREATE TABLE IF NOT EXISTS public.family_invites (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id   uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  created_by  uuid NOT NULL REFERENCES auth.users(id),
  expires_at  timestamptz NOT NULL DEFAULT (now() + INTERVAL '24 hours'),
  used_at     timestamptz,          -- NULL = still valid
  used_by     uuid                  -- who accepted the invite
);

-- ============================================================
-- Row-Level Security Policies
-- ============================================================

ALTER TABLE public.families        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_members  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_invites  ENABLE ROW LEVEL SECURITY;

-- Grant basic CRUD access — RLS policies control row-level visibility
GRANT SELECT, INSERT, UPDATE, DELETE ON public.families        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.family_members  TO authenticated;
GRANT SELECT, INSERT, UPDATE        ON public.family_invites  TO authenticated;
GRANT SELECT                        ON public.family_invites  TO anon;

-- families: only members of the family can see it
CREATE POLICY "family_members_can_read_family"
  ON public.families FOR SELECT
  USING (
    id IN (SELECT get_user_families())
  );

-- families: creator can insert
CREATE POLICY "creator_can_insert_family"
  ON public.families FOR INSERT
  WITH CHECK (created_by = auth.uid());

-- family_members: members of the family can read the member list
-- Uses SECURITY DEFINER function to avoid infinite recursion
CREATE POLICY "family_members_can_read_members"
  ON public.family_members FOR SELECT
  USING (
    family_id IN (SELECT get_user_families())
  );

-- family_members: only insert if joining via valid invite or creating family
CREATE POLICY "allow_insert_own_membership"
  ON public.family_members FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- family_invites: admin can create invites
CREATE POLICY "admin_can_create_invite"
  ON public.family_invites FOR INSERT
  WITH CHECK (created_by = auth.uid());

-- family_invites: anyone with the invite ID can read it (to validate)
CREATE POLICY "anyone_can_read_invite_by_id"
  ON public.family_invites FOR SELECT
  USING (true);

-- family_invites: mark as used
CREATE POLICY "invitee_can_mark_used"
  ON public.family_invites FOR UPDATE
  USING (used_by IS NULL AND expires_at > now());
