-- ============================================================
-- Migration: Normalize family_members.role from ENUM to TEXT
--
-- Problem: core_schema.sql defined role as `family_role` ENUM
-- with uppercase values ('ADMIN', 'PARENT', 'CHILD', etc.),
-- but the Dart app uses lowercase TEXT ('admin', 'member', etc.).
-- This causes INSERT failures with:
--   "22P02 invalid input value for enum family_role"
--
-- Solution: Convert the column to TEXT and normalize values
-- to lowercase, matching the Dart FamilyRole constants.
-- ============================================================

-- Step 1: Add a temporary TEXT column
ALTER TABLE public.family_members
  ADD COLUMN IF NOT EXISTS role_text TEXT;

-- Step 2: Copy existing values as lowercase
UPDATE public.family_members
  SET role_text = lower(role::text);

-- Step 3: Map 'child' (ENUM value) → 'member' (Dart constant)
-- The core_schema ENUM used 'CHILD' but Dart uses 'member'
UPDATE public.family_members
  SET role_text = 'member'
  WHERE role_text = 'child';

-- Step 4: Drop the old ENUM column
ALTER TABLE public.family_members
  DROP COLUMN role;

-- Step 5: Rename temp column to 'role'
ALTER TABLE public.family_members
  RENAME COLUMN role_text TO role;

-- Step 6: Set NOT NULL and default
ALTER TABLE public.family_members
  ALTER COLUMN role SET NOT NULL,
  ALTER COLUMN role SET DEFAULT 'member';

-- Step 7: Ensure joined_at column exists (families.sql added it,
-- but core_schema.sql used created_at instead)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'family_members'
      AND column_name = 'joined_at'
  ) THEN
    ALTER TABLE public.family_members
      ADD COLUMN joined_at TIMESTAMPTZ NOT NULL DEFAULT now();
    -- Copy existing created_at values if the column exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'family_members'
        AND column_name = 'created_at'
    ) THEN
      UPDATE public.family_members SET joined_at = created_at;
    END IF;
  END IF;
END $$;
