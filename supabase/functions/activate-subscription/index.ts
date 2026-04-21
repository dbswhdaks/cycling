import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type PlanType = 'monthly' | 'yearly';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function resolvePlan(payload: Record<string, unknown>): {
  plan: PlanType;
  periodDays: number;
} {
  const planValue = (payload['plan'] ?? 'monthly').toString().toLowerCase();
  const plan: PlanType = planValue === 'yearly' ? 'yearly' : 'monthly';
  const periodDays = plan === 'yearly' ? 365 : 30;
  return { plan, periodDays };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const authHeader = req.headers.get('Authorization');

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return jsonResponse({ error: 'Missing Supabase env vars' }, 500);
    }
    if (!authHeader) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const {
      data: { user },
      error: userError,
    } = await authClient.auth.getUser();
    if (userError != null || user == null) {
      return jsonResponse({ error: 'Invalid user token' }, 401);
    }

    const payload = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const { plan, periodDays } = resolvePlan(payload);

    const nowUtc = new Date();
    const expiresAt = new Date(nowUtc.getTime() + periodDays * 24 * 60 * 60 * 1000);

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { error: upsertError } = await adminClient.from('subscriptions').upsert(
      {
        user_id: user.id,
        plan,
        status: 'active',
        period_days: periodDays,
        started_at: nowUtc.toISOString(),
        expires_at: expiresAt.toISOString(),
        updated_at: nowUtc.toISOString(),
      },
      { onConflict: 'user_id' },
    );

    if (upsertError != null) {
      return jsonResponse(
        { error: 'Failed to save subscription', details: upsertError.message },
        500,
      );
    }

    return jsonResponse({
      success: true,
      plan,
      period_days: periodDays,
      expires_at: expiresAt.toISOString(),
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : 'Unknown error';
    return jsonResponse({ error: message }, 500);
  }
});
