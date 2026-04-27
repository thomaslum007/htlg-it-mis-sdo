
-- PROFILES
DROP POLICY IF EXISTS "auth read all profiles" ON public.profiles;

CREATE POLICY "users read own profile or admin reads all"
ON public.profiles FOR SELECT
TO authenticated
USING (id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.list_profiles_public()
RETURNS TABLE (
  id uuid,
  name text,
  username text,
  dept text,
  avatar_color text,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, name, username, dept, avatar_color, created_at
  FROM public.profiles
$$;

REVOKE ALL ON FUNCTION public.list_profiles_public() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.list_profiles_public() TO authenticated;

-- ISSUES
DROP POLICY IF EXISTS "auth write issues" ON public.issues;

CREATE POLICY "auth insert issues"
ON public.issues FOR INSERT
TO authenticated
WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "creator or admin update issues"
ON public.issues FOR UPDATE
TO authenticated
USING (created_by = auth.uid()::text OR public.has_role(auth.uid(), 'admin'))
WITH CHECK (created_by = auth.uid()::text OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "creator or admin delete issues"
ON public.issues FOR DELETE
TO authenticated
USING (created_by = auth.uid()::text OR public.has_role(auth.uid(), 'admin'));

-- WORKSTREAMS
DROP POLICY IF EXISTS "auth write workstreams" ON public.workstreams;

CREATE POLICY "admins write workstreams"
ON public.workstreams FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));
