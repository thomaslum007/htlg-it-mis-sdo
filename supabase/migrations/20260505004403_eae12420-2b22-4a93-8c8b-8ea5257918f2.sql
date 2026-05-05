-- Make issue keys unique so import can deduplicate by key
-- First, null out empty strings and resolve any duplicates by appending suffixes
UPDATE public.issues SET key = NULL WHERE key IS NOT NULL AND length(trim(key)) = 0;

-- Resolve duplicate keys by suffixing -dup1, -dup2, etc.
WITH dups AS (
  SELECT id, key,
    row_number() OVER (PARTITION BY key ORDER BY created_at) AS rn
  FROM public.issues
  WHERE key IS NOT NULL
)
UPDATE public.issues i
SET key = i.key || '-dup' || (d.rn - 1)
FROM dups d
WHERE i.id = d.id AND d.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS issues_key_unique_idx ON public.issues (key) WHERE key IS NOT NULL;