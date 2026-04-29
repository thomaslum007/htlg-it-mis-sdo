DROP POLICY IF EXISTS "creator or admin update issues" ON public.issues;

CREATE POLICY "creator admin or pm update issues"
ON public.issues
FOR UPDATE
TO authenticated
USING (
  created_by = auth.uid()::text
  OR public.has_role(auth.uid(), 'admin'::public.app_role)
  OR public.has_role(auth.uid(), 'pm'::public.app_role)
)
WITH CHECK (
  created_by = auth.uid()::text
  OR public.has_role(auth.uid(), 'admin'::public.app_role)
  OR public.has_role(auth.uid(), 'pm'::public.app_role)
);