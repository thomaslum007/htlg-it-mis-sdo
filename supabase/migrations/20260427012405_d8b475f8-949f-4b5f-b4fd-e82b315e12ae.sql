
-- ============================================================
-- 1. Roles enum + user_roles table + has_role() SECURITY DEFINER
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'pm', 'dev', 'viewer');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.user_roles (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.user_roles
  WHERE user_id = auth.uid()
  ORDER BY CASE role WHEN 'admin' THEN 1 WHEN 'pm' THEN 2 WHEN 'dev' THEN 3 WHEN 'viewer' THEN 4 END
  LIMIT 1
$$;

-- user_roles RLS
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "admins manage roles" ON public.user_roles;
CREATE POLICY "admins manage roles" ON public.user_roles
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- ============================================================
-- 2. Profiles table (linked to auth.users)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id               uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name             text NOT NULL DEFAULT '',
  username         text,
  email            text,
  dept             text,
  responsibilities text,
  avatar_color     text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS profiles_set_updated_at ON public.profiles;
CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

DROP POLICY IF EXISTS "auth read all profiles" ON public.profiles;
CREATE POLICY "auth read all profiles" ON public.profiles
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid() OR public.has_role(auth.uid(), 'admin'))
  WITH CHECK (id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "admins delete profiles" ON public.profiles;
CREATE POLICY "admins delete profiles" ON public.profiles
  FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- Insert is handled by the on-signup trigger; no INSERT policy needed for clients.

-- ============================================================
-- 3. Auto-create profile + role on signup
--    First user becomes admin; everyone else viewer.
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_first boolean;
  assigned_role public.app_role;
BEGIN
  SELECT NOT EXISTS (SELECT 1 FROM public.profiles) INTO is_first;
  assigned_role := CASE WHEN is_first THEN 'admin'::public.app_role ELSE 'viewer'::public.app_role END;

  INSERT INTO public.profiles (id, name, username, email, dept, responsibilities, avatar_color)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name',     split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
    NEW.email,
    NULLIF(NEW.raw_user_meta_data->>'dept', ''),
    NULLIF(NEW.raw_user_meta_data->>'responsibilities', ''),
    NULLIF(NEW.raw_user_meta_data->>'avatar_color', '')
  );

  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, assigned_role)
    ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 4. Drop the old app_users table (plaintext passwords)
--    First remove from realtime publication.
-- ============================================================
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.app_users;
EXCEPTION WHEN undefined_object OR undefined_table THEN NULL; END $$;

DROP TABLE IF EXISTS public.app_users CASCADE;

-- ============================================================
-- 5. Lock down existing tables: replace anon-all with auth-only
-- ============================================================

-- ISSUES
DROP POLICY IF EXISTS "anon all issues" ON public.issues;
DROP POLICY IF EXISTS "auth read issues" ON public.issues;
DROP POLICY IF EXISTS "auth write issues" ON public.issues;

CREATE POLICY "auth read issues" ON public.issues
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth write issues" ON public.issues
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- WORKSTREAMS
DROP POLICY IF EXISTS "anon all workstreams" ON public.workstreams;
DROP POLICY IF EXISTS "auth read workstreams" ON public.workstreams;
DROP POLICY IF EXISTS "auth write workstreams" ON public.workstreams;

CREATE POLICY "auth read workstreams" ON public.workstreams
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth write workstreams" ON public.workstreams
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- ACTIVITIES
DROP POLICY IF EXISTS "anon all activities" ON public.activities;
DROP POLICY IF EXISTS "auth read activities" ON public.activities;
DROP POLICY IF EXISTS "auth insert activities" ON public.activities;
DROP POLICY IF EXISTS "admins delete activities" ON public.activities;

CREATE POLICY "auth read activities" ON public.activities
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth insert activities" ON public.activities
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "admins delete activities" ON public.activities
  FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- SETTINGS_KV (admin write only)
DROP POLICY IF EXISTS "anon all settings" ON public.settings_kv;
DROP POLICY IF EXISTS "auth read settings" ON public.settings_kv;
DROP POLICY IF EXISTS "admins write settings" ON public.settings_kv;

CREATE POLICY "auth read settings" ON public.settings_kv
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "admins write settings" ON public.settings_kv
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- ============================================================
-- 6. Make sure profiles + user_roles + workstreams + issues
--    are part of realtime publication for live sync
-- ============================================================
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.user_roles;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
