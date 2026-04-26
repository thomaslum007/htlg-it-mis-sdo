-- ============ TABLES ============

CREATE TABLE public.app_users (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  name TEXT NOT NULL,
  email TEXT,
  role TEXT NOT NULL DEFAULT 'viewer',
  dept TEXT,
  avatar_color TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.workstreams (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  dept TEXT,
  description TEXT,
  color TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.issues (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  key TEXT,
  title TEXT NOT NULL,
  description TEXT,
  type TEXT,
  status TEXT,
  priority TEXT,
  assignee TEXT,
  workstream TEXT,
  labels JSONB NOT NULL DEFAULT '[]'::jsonb,
  checklist JSONB NOT NULL DEFAULT '[]'::jsonb,
  start_date DATE,
  end_date DATE,
  created_by TEXT,
  created_by_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.activities (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT,
  user_name TEXT,
  action TEXT NOT NULL,
  target TEXT,
  target_id TEXT,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.settings_kv (
  key TEXT NOT NULL PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ TRIGGERS for updated_at ============
CREATE OR REPLACE FUNCTION public.tg_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER trg_app_users_updated   BEFORE UPDATE ON public.app_users   FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();
CREATE TRIGGER trg_workstreams_updated BEFORE UPDATE ON public.workstreams FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();
CREATE TRIGGER trg_issues_updated      BEFORE UPDATE ON public.issues      FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();
CREATE TRIGGER trg_settings_updated    BEFORE UPDATE ON public.settings_kv FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- ============ RLS (open shared workspace; app handles auth) ============
ALTER TABLE public.app_users   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workstreams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issues      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings_kv ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon all app_users"   ON public.app_users   FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon all workstreams" ON public.workstreams FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon all issues"      ON public.issues      FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon all activities"  ON public.activities  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon all settings"    ON public.settings_kv FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ============ REALTIME ============
ALTER TABLE public.app_users   REPLICA IDENTITY FULL;
ALTER TABLE public.workstreams REPLICA IDENTITY FULL;
ALTER TABLE public.issues      REPLICA IDENTITY FULL;
ALTER TABLE public.activities  REPLICA IDENTITY FULL;
ALTER TABLE public.settings_kv REPLICA IDENTITY FULL;

ALTER PUBLICATION supabase_realtime ADD TABLE public.app_users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.workstreams;
ALTER PUBLICATION supabase_realtime ADD TABLE public.issues;
ALTER PUBLICATION supabase_realtime ADD TABLE public.activities;
ALTER PUBLICATION supabase_realtime ADD TABLE public.settings_kv;

-- ============ SEED DATA ============
INSERT INTO public.app_users (username, password, name, email, role, dept, avatar_color) VALUES
  ('admin', 'admin123', 'Alice Admin',     'alice@flowdesk.app', 'admin',  'Operations',  '#6366f1'),
  ('bob',   'bob123',   'Bob Manager',     'bob@flowdesk.app',   'pm',     'Engineering', '#10b981'),
  ('carol', 'carol123', 'Carol Developer', 'carol@flowdesk.app', 'dev',    'Engineering', '#f59e0b'),
  ('dave',  'dave123',  'Dave Developer',  'dave@flowdesk.app',  'dev',    'Engineering', '#ef4444'),
  ('eve',   'eve123',   'Eve Viewer',      'eve@flowdesk.app',   'viewer', 'Operations',  '#8b5cf6')
ON CONFLICT (username) DO NOTHING;

INSERT INTO public.settings_kv (key, value) VALUES
  ('general', '{"appName":"FlowDesk","theme":"dark"}'::jsonb),
  ('labels', '["frontend","backend","bug","urgent","ux","infra","docs"]'::jsonb),
  ('statuses', '["To Do","In Progress","Review","Blocked","Completed"]'::jsonb),
  ('types', '["Task","Bug","Story","Epic"]'::jsonb),
  ('priorities', '["Low","Medium","High","Critical"]'::jsonb),
  ('roles_perm', '{
    "admin":  {"view":["dashboard","issues","kanban","gantt","focus","team","workstreams","users","settings"],"interact":["dashboard","issues","kanban","gantt","focus","team","workstreams","users","settings"]},
    "pm":     {"view":["dashboard","issues","kanban","gantt","focus","team","workstreams","users","settings"],"interact":["dashboard","issues","kanban","gantt","focus","workstreams"]},
    "dev":    {"view":["dashboard","issues","kanban","gantt","focus","team","workstreams"],"interact":["issues","kanban","focus"]},
    "viewer": {"view":["dashboard","issues","kanban","gantt","focus","team","workstreams"],"interact":["focus"]}
  }'::jsonb),
  ('dashboard_segments', '{
    "in_progress":["In Progress","Review"],
    "completed":["Completed"],
    "need_attention":["Blocked"]
  }'::jsonb)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.workstreams (name, dept, description, color) VALUES
  ('Platform',   'Engineering', 'Core platform infrastructure',     '#6366f1'),
  ('Mobile App', 'Engineering', 'iOS and Android applications',     '#10b981'),
  ('Operations', 'Operations',  'Day-to-day operational workflows', '#f59e0b')
ON CONFLICT DO NOTHING;