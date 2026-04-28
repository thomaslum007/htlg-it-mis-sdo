
-- Function to derive a workstream prefix (uppercase, alpha only, first 3 chars; fallback TKT)
CREATE OR REPLACE FUNCTION public.derive_ws_prefix(_workstream text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  cleaned text;
BEGIN
  IF _workstream IS NULL OR length(trim(_workstream)) = 0 THEN
    RETURN 'TKT';
  END IF;
  cleaned := upper(regexp_replace(_workstream, '[^A-Za-z]', '', 'g'));
  IF length(cleaned) = 0 THEN
    RETURN 'TKT';
  END IF;
  RETURN substr(cleaned, 1, 3);
END;
$$;

-- Trigger: assign issues.key on insert (PREFIX-NNNN), increment per prefix
CREATE OR REPLACE FUNCTION public.assign_issue_key()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  prefix text;
  next_num int;
BEGIN
  IF NEW.key IS NOT NULL AND length(trim(NEW.key)) > 0 THEN
    RETURN NEW;
  END IF;
  prefix := public.derive_ws_prefix(NEW.workstream);
  SELECT COALESCE(MAX( CAST(substring(key FROM '[0-9]+$') AS int) ), 0) + 1
    INTO next_num
    FROM public.issues
    WHERE key LIKE prefix || '-%'
      AND key ~ ('^' || prefix || '-[0-9]+$');
  NEW.key := prefix || '-' || lpad(next_num::text, 4, '0');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_issue_key ON public.issues;
CREATE TRIGGER trg_assign_issue_key
BEFORE INSERT ON public.issues
FOR EACH ROW EXECUTE FUNCTION public.assign_issue_key();

-- Backfill existing rows that have NULL/empty key, ordered by created_at, grouped by prefix
DO $$
DECLARE
  r record;
  prefix text;
  next_num int;
BEGIN
  FOR r IN SELECT id, workstream FROM public.issues
           WHERE key IS NULL OR length(trim(key)) = 0
           ORDER BY created_at ASC, id ASC
  LOOP
    prefix := public.derive_ws_prefix(r.workstream);
    SELECT COALESCE(MAX( CAST(substring(key FROM '[0-9]+$') AS int) ), 0) + 1
      INTO next_num
      FROM public.issues
      WHERE key LIKE prefix || '-%'
        AND key ~ ('^' || prefix || '-[0-9]+$');
    UPDATE public.issues SET key = prefix || '-' || lpad(next_num::text, 4, '0') WHERE id = r.id;
  END LOOP;
END $$;

-- Index for fast lookup by key
CREATE INDEX IF NOT EXISTS idx_issues_key ON public.issues(key);
