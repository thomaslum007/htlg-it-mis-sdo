ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS force_password_reset boolean NOT NULL DEFAULT false;

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
SECURITY DEFINER
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