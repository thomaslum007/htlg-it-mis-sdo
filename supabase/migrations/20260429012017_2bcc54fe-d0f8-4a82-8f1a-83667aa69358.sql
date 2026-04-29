DROP FUNCTION IF EXISTS public.list_profiles_public();

CREATE OR REPLACE FUNCTION public.list_profiles_public()
RETURNS TABLE(
  id uuid,
  name text,
  username text,
  email text,
  dept text,
  responsibilities text,
  avatar_color text,
  force_password_reset boolean,
  created_at timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
  SELECT
    p.id,
    p.name,
    p.username,
    p.email,
    p.dept,
    p.responsibilities,
    p.avatar_color,
    p.force_password_reset,
    p.created_at
  FROM public.profiles p;
$$;

DROP POLICY IF EXISTS "users read own profile or admin reads all" ON public.profiles;

CREATE POLICY "signed in users read team profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (auth.uid() IS NOT NULL);

REVOKE ALL ON FUNCTION public.list_profiles_public() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_profiles_public() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_profiles_public() TO authenticated;