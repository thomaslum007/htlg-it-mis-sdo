
-- 1. list_profiles_public: drop & recreate without force_password_reset, SECURITY INVOKER
DROP FUNCTION IF EXISTS public.list_profiles_public();
CREATE FUNCTION public.list_profiles_public()
 RETURNS TABLE(id uuid, name text, username text, email text, dept text, responsibilities text, avatar_color text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
 SET search_path TO 'public'
AS $function$
  SELECT p.id, p.name, p.username, p.email, p.dept, p.responsibilities, p.avatar_color, p.created_at
  FROM public.profiles p;
$function$;

-- 2. activities: prevent spoofing user_id
DROP POLICY IF EXISTS "auth insert activities" ON public.activities;
CREATE POLICY "auth insert activities" ON public.activities
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND (user_id IS NULL OR user_id = (auth.uid())::text)
  );

-- 3. issues: restrict INSERT/UPDATE/DELETE to non-viewer roles
DROP POLICY IF EXISTS "auth insert issues" ON public.issues;
CREATE POLICY "non-viewers insert issues" ON public.issues
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND (
      public.has_role(auth.uid(), 'admin'::public.app_role)
      OR public.has_role(auth.uid(), 'pm'::public.app_role)
      OR public.has_role(auth.uid(), 'dev'::public.app_role)
    )
  );

DROP POLICY IF EXISTS "creator admin or pm update issues" ON public.issues;
CREATE POLICY "non-viewer update issues" ON public.issues
  FOR UPDATE TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'pm'::public.app_role)
    OR (created_by = (auth.uid())::text AND public.has_role(auth.uid(), 'dev'::public.app_role))
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'pm'::public.app_role)
    OR (created_by = (auth.uid())::text AND public.has_role(auth.uid(), 'dev'::public.app_role))
  );

DROP POLICY IF EXISTS "creator or admin delete issues" ON public.issues;
CREATE POLICY "creator non-viewer or admin delete issues" ON public.issues
  FOR DELETE TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR (
      created_by = (auth.uid())::text
      AND (
        public.has_role(auth.uid(), 'pm'::public.app_role)
        OR public.has_role(auth.uid(), 'dev'::public.app_role)
      )
    )
  );

-- 4. Remove user_roles from realtime publication (only if present)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='user_roles'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime DROP TABLE public.user_roles';
  END IF;
END$$;

-- 5. Realtime channel scoping: only allow user-scoped topic "user:{auth.uid()}"
DROP POLICY IF EXISTS "users subscribe own channel" ON realtime.messages;
CREATE POLICY "users subscribe own channel" ON realtime.messages
  FOR SELECT TO authenticated
  USING (
    realtime.topic() = ('user:' || (auth.uid())::text)
  );

DROP POLICY IF EXISTS "users broadcast own channel" ON realtime.messages;
CREATE POLICY "users broadcast own channel" ON realtime.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    realtime.topic() = ('user:' || (auth.uid())::text)
  );

-- 6. helpful_links: server-side scheme validation
CREATE OR REPLACE FUNCTION public.helpful_links_validate_url()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.url !~* '^https?://' THEN
    RAISE EXCEPTION 'Only http(s) URLs are allowed in helpful_links';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS helpful_links_validate_url_trg ON public.helpful_links;
CREATE TRIGGER helpful_links_validate_url_trg
  BEFORE INSERT OR UPDATE ON public.helpful_links
  FOR EACH ROW EXECUTE FUNCTION public.helpful_links_validate_url();
