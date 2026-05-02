CREATE OR REPLACE FUNCTION public.helpful_links_cap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
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