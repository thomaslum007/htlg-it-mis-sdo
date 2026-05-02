-- 1) Add workstream column to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS workstream text;

-- 2) Helpful Links table
CREATE TABLE IF NOT EXISTS public.helpful_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  url text NOT NULL,
  "order" int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.helpful_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth read helpful_links" ON public.helpful_links;
CREATE POLICY "auth read helpful_links"
  ON public.helpful_links FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "admins write helpful_links" ON public.helpful_links;
CREATE POLICY "admins write helpful_links"
  ON public.helpful_links FOR ALL
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

-- updated_at trigger
DROP TRIGGER IF EXISTS trg_helpful_links_updated ON public.helpful_links;
CREATE TRIGGER trg_helpful_links_updated
  BEFORE UPDATE ON public.helpful_links
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- Cap at 20 rows
CREATE OR REPLACE FUNCTION public.helpful_links_cap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.helpful_links;
  IF cnt >= 20 THEN
    RAISE EXCEPTION 'Maximum of 20 helpful links allowed';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_helpful_links_cap ON public.helpful_links;
CREATE TRIGGER trg_helpful_links_cap
  BEFORE INSERT ON public.helpful_links
  FOR EACH ROW EXECUTE FUNCTION public.helpful_links_cap();

-- 3) Seed canonical default permissions if roles_perm key missing
INSERT INTO public.settings_kv (key, value)
SELECT 'roles_perm', '{
  "admin":  {"view":["dashboard","issues","kanban","gantt","focus","workstreams","settings"],"interact":["dashboard","issues","kanban","gantt","focus","workstreams","settings"]},
  "pm":     {"view":["dashboard","issues","kanban","gantt","focus","workstreams","settings"],"interact":["dashboard","issues","kanban","gantt","focus","workstreams"]},
  "dev":    {"view":["dashboard","issues","kanban","gantt","focus","workstreams"],"interact":["issues","kanban","gantt","focus"]},
  "viewer": {"view":["dashboard","issues","kanban","gantt","focus","workstreams"],"interact":["focus"]}
}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.settings_kv WHERE key='roles_perm');