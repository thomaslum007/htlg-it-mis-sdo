-- Drop partial unique index and replace with a full unique constraint so PostgREST upsert(onConflict:'key') works.
-- Existing NULL keys remain allowed: a UNIQUE constraint treats multiple NULLs as distinct in Postgres.
DROP INDEX IF EXISTS public.issues_key_unique_idx;
ALTER TABLE public.issues DROP CONSTRAINT IF EXISTS issues_key_unique;
ALTER TABLE public.issues ADD CONSTRAINT issues_key_unique UNIQUE (key);