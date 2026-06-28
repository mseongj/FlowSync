-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

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

-- 4. Events Policies
-- PUBLIC: Visible to anyone in the family
CREATE POLICY "Public events visible to family" ON public.events
FOR SELECT USING (
  privacy_level = 'PUBLIC' AND family_id IN (SELECT get_user_families())
);

-- PRIVATE: Visible to creator, or anyone with role PARENT in that family
CREATE POLICY "Private events visible to creator or parents" ON public.events
FOR SELECT USING (
  privacy_level = 'PRIVATE' AND (
    creator_id = auth.uid() OR 
    EXISTS (
      SELECT 1 FROM public.family_members 
      WHERE family_id = events.family_id AND user_id = auth.uid() AND role = 'PARENT'
    )
  )
);

-- SECRET: Strictly visible to creator only
CREATE POLICY "Secret events strictly visible to creator" ON public.events
FOR SELECT USING (
  privacy_level = 'SECRET' AND creator_id = auth.uid()
);

-- ALL: Users can insert events into their family
CREATE POLICY "Users can insert events in their family" ON public.events
FOR INSERT WITH CHECK (family_id IN (SELECT get_user_families()) AND creator_id = auth.uid());

-- ALL: Users can update their own events
CREATE POLICY "Users can update their own events" ON public.events
FOR UPDATE USING (creator_id = auth.uid());

-- NOTE: DELETE policy is intentionally omitted to maintain offline sync integrity.
-- Clients (Flutter) must perform a Soft Delete by updating the `deleted_at` column.
-- Hard deletion is handled asynchronously by the pg_cron background job.
