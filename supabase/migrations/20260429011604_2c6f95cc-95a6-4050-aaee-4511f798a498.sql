REVOKE ALL ON FUNCTION public.list_profiles_public() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_profiles_public() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_profiles_public() TO authenticated;