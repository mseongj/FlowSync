-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;

-- Helper function to get user's families
CREATE OR REPLACE FUNCTION get_user_families()
RETURNS SETOF UUID AS $$
  SELECT family_id FROM public.family_members WHERE user_id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 1. Users Policies
CREATE POLICY "Users can view members of their families" ON public.users
FOR SELECT USING (
  id IN (
    SELECT user_id FROM public.family_members WHERE family_id IN (SELECT get_user_families())
  )
  OR id = auth.uid()
);

CREATE POLICY "Users can update their own profile" ON public.users
FOR UPDATE USING (id = auth.uid());

-- 2. Families Policies
CREATE POLICY "Users can view their own families" ON public.families
FOR SELECT USING (id IN (SELECT get_user_families()));

-- 3. Family Members Policies
CREATE POLICY "Users can view family members of their families" ON public.family_members
FOR SELECT USING (family_id IN (SELECT get_user_families()));

-- NOTE: Event-level RLS policies are defined in teen_privacy_rls.sql
-- on the `calendar_events` table (the legacy `events` table was dropped
-- in migration 20260829000001_drop_unused_events_table.sql).

