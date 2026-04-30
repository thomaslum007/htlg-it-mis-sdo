-- dashboard_layouts: per-user widget layout + global filters
CREATE TABLE IF NOT EXISTS public.dashboard_layouts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  layout jsonb NOT NULL DEFAULT '[]'::jsonb,
  filters jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.dashboard_layouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users read own layout"
  ON public.dashboard_layouts FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "users upsert own layout"
  ON public.dashboard_layouts FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "users update own layout"
  ON public.dashboard_layouts FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "users delete own layout"
  ON public.dashboard_layouts FOR DELETE TO authenticated
  USING (user_id = auth.uid());

CREATE TRIGGER dashboard_layouts_set_updated_at
  BEFORE UPDATE ON public.dashboard_layouts
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();