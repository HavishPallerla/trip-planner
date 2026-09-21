import { describe, it, expect, afterAll } from 'vitest';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const admin = createSupabaseClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const allowedEmail = `signup-allowed-${Date.now()}@example.com`;
const blockedEmail = `signup-blocked-${Date.now()}@example.com`;
let allowedUserId: string | undefined;

afterAll(async () => {
  if (allowedUserId) await admin.auth.admin.deleteUser(allowedUserId);
  await admin.from('allowed_emails').delete().eq('email', allowedEmail);
});

describe('signup gating trigger', () => {
  it('allows signup for an allowlisted email and creates a profile', async () => {
    await admin.from('allowed_emails').insert({ email: allowedEmail });
    const { data, error } = await admin.auth.admin.createUser({
      email: allowedEmail,
      password: 'test-password-12345',
      email_confirm: true,
    });
    expect(error).toBeNull();
    allowedUserId = data.user!.id;

    const { data: profile } = await admin
      .from('profiles')
      .select('*')
      .eq('id', allowedUserId)
      .single();
    expect(profile?.email).toBe(allowedEmail);
  });

  it('rejects signup for a non-allowlisted email', async () => {
    const { error } = await admin.auth.admin.createUser({
      email: blockedEmail,
      password: 'test-password-12345',
      email_confirm: true,
    });
    expect(error).not.toBeNull();
  });
});
