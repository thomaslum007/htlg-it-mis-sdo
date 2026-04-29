import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const roleRank: Record<string, number> = { admin: 1, pm: 2, dev: 3, viewer: 4 };
const allowedRoles = new Set(['admin', 'pm', 'dev', 'viewer']);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_PUBLISHABLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY');
    if (!url || !serviceKey || !anonKey) return json({ error: 'Server configuration is missing.' }, 500);

    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'Sign in required.' }, 401);

    const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
    const service = createClient(url, serviceKey);

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return json({ error: 'Invalid session.' }, 401);

    const { data: roles, error: roleError } = await service
      .from('user_roles')
      .select('role')
      .eq('user_id', authData.user.id);
    if (roleError) return json({ error: roleError.message }, 500);
    const bestRole = (roles || []).map((r: { role: string }) => r.role).sort((a, b) => (roleRank[a] || 99) - (roleRank[b] || 99))[0];
    if (bestRole !== 'admin') return json({ error: 'Admin access required.' }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || '');

    if (action === 'create') {
      const email = String(body.email || '').trim().toLowerCase();
      const password = String(body.password || '');
      const name = String(body.name || '').trim() || email.split('@')[0];
      const username = String(body.username || '').trim() || email.split('@')[0];
      const role = allowedRoles.has(body.role) ? body.role : 'viewer';
      if (!email || !password) return json({ error: 'Email and password are required.' }, 400);
      if (password.length < 6) return json({ error: 'Password must be at least 6 characters.' }, 400);

      const { data, error } = await service.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, username },
      });
      if (error || !data.user) return json({ error: error?.message || 'Could not create user.' }, 400);

      const profileRow = {
        id: data.user.id,
        name,
        username,
        email,
        dept: body.dept ? String(body.dept) : null,
        responsibilities: body.responsibilities ? String(body.responsibilities) : null,
        force_password_reset: !!body.forcePasswordReset,
      };
      const { error: profileError } = await service.from('profiles').upsert(profileRow);
      if (profileError) return json({ error: profileError.message }, 500);
      await service.from('user_roles').delete().eq('user_id', data.user.id);
      const { error: userRoleError } = await service.from('user_roles').insert({ user_id: data.user.id, role });
      if (userRoleError) return json({ error: userRoleError.message }, 500);

      return json({ userId: data.user.id });
    }

    if (action === 'update') {
      const userId = String(body.userId || '');
      const role = allowedRoles.has(body.role) ? body.role : 'viewer';
      if (!userId) return json({ error: 'User is required.' }, 400);
      const password = String(body.password || '');
      if (password && password.length < 6) return json({ error: 'Password must be at least 6 characters.' }, 400);

      const updates: Record<string, unknown> = {};
      if (body.email) updates.email = String(body.email).trim().toLowerCase();
      if (password) updates.password = password;
      if (Object.keys(updates).length) {
        const { error } = await service.auth.admin.updateUserById(userId, updates);
        if (error) return json({ error: error.message }, 400);
      }

      const profileRow = {
        name: String(body.name || '').trim(),
        username: String(body.username || '').trim(),
        email: body.email ? String(body.email).trim().toLowerCase() : null,
        dept: body.dept ? String(body.dept) : null,
        responsibilities: body.responsibilities ? String(body.responsibilities) : null,
        force_password_reset: !!body.forcePasswordReset,
      };
      const { error: profileError } = await service.from('profiles').update(profileRow).eq('id', userId);
      if (profileError) return json({ error: profileError.message }, 500);
      await service.from('user_roles').delete().eq('user_id', userId);
      const { error: userRoleError } = await service.from('user_roles').insert({ user_id: userId, role });
      if (userRoleError) return json({ error: userRoleError.message }, 500);

      return json({ userId });
    }

    if (action === 'delete') {
      const userId = String(body.userId || '');
      if (!userId) return json({ error: 'User is required.' }, 400);
      if (userId === authData.user.id) return json({ error: 'You cannot delete your own admin account.' }, 400);
      const { error } = await service.auth.admin.deleteUser(userId);
      if (error) return json({ error: error.message }, 400);
      return json({ userId });
    }

    return json({ error: 'Unknown action.' }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unexpected server error.' }, 500);
  }
});
