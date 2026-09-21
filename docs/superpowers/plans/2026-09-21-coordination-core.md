# Trip Planner — Coordination Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the phase 1 coordination core — auth, roster, trip creation, manual item proposals with confirmation/cost-breakdown, shared calendar, and ICS export.

**Architecture:** Next.js (App Router, TypeScript) app backed by Supabase (Postgres + Auth). Mutations use Server Actions; reads use Supabase server/browser clients. RLS enforces that only a trip's participants can see/write its data. A single `is_trip_participant()` SQL helper function backs every trip-scoped policy.

**Tech Stack:** Next.js (App Router), TypeScript, Tailwind CSS, Supabase (`@supabase/supabase-js`, `@supabase/ssr`), Vitest, `date-fns`.

**Spec:** `docs/superpowers/specs/2026-09-21-coordination-core-design.md`

## Global Constraints

- Supabase project URL: `https://wgsonxheqjvzgfuhbuts.supabase.co` (project ref `wgsonxheqjvzgfuhbuts`).
- Env vars (in `.env.local`, gitignored, never committed): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
- Auth is magic-link only. No password login in the app UI (test scripts use `admin.createUser` with a password purely to obtain a session for RLS testing — that's a test-only mechanism, not a user-facing feature).
- Roster is closed: only emails present in `allowed_emails` may complete signup (enforced by a Postgres trigger, not app code).
- Calendar sync is one-way ICS export only. No Google OAuth.
- No Docker/local Supabase — all schema work targets the real hosted project directly.
- Every task's last step before committing must include running `npm run build` and confirming it succeeds (this type-checks and lints the whole project).
- All new library code (`lib/*.ts`) must be plain functions with no side effects where the task calls for a "pure function" — this is what makes them unit-testable without a live database.

## Prerequisites (one-time, outside the task loop)

These must happen before the tasks that need them. They are **not** delegated to a subagent because they require interactive login with your own credentials.

1. **Supabase API keys** — from the Supabase dashboard → Project Settings → API, get the `anon` `public` key and the `service_role` `secret` key. Needed before Task 2 can be verified.
2. **CLI link** — run once, interactively:
   ```
   supabase login
   supabase link --project-ref wgsonxheqjvzgfuhbuts
   ```
   `link` will prompt for the database password (set when the project was created). Needed before Task 3's `supabase db push` will work.

If a task below reaches a `supabase db push` or a step requiring real keys and the prerequisite hasn't happened yet, the subagent should stop and report back rather than skip verification.

---

### Task 1: Project scaffolding

**Files:**
- Create: entire Next.js project (via `create-next-app`) at `~/trip-planner`
- Create: `vitest.config.ts`
- Create: `vitest.setup.ts`
- Create: `lib/smoke.test.ts`
- Modify: `package.json` (add `test` script)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: a working Next.js + TypeScript + Tailwind app with `@/*` import alias; a working Vitest runner that loads `.env.local` via `vitest.setup.ts`.

- [ ] **Step 1: Scaffold the Next.js app**

```bash
cd ~/trip-planner
npx create-next-app@latest . --typescript --tailwind --app --no-src-dir --import-alias "@/*" --eslint --use-npm
```

When prompted about the current directory not being empty (it has `docs/` and `.git/`), confirm to proceed.

- [ ] **Step 2: Install test dependencies**

```bash
npm install -D vitest dotenv
```

- [ ] **Step 3: Add Vitest config**

`vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    environment: 'node',
    setupFiles: ['./vitest.setup.ts'],
  },
  resolve: {
    alias: { '@': path.resolve(__dirname, '.') },
  },
});
```

`vitest.setup.ts`:
```ts
import { config } from 'dotenv';
config({ path: '.env.local' });
```

- [ ] **Step 4: Add the `test` script**

In `package.json`, add to `"scripts"`:
```json
"test": "vitest run"
```

- [ ] **Step 5: Write a smoke test**

`lib/smoke.test.ts`:
```ts
import { describe, it, expect } from 'vitest';

describe('smoke', () => {
  it('runs', () => {
    expect(1 + 1).toBe(2);
  });
});
```

- [ ] **Step 6: Run the test suite**

Run: `npm test`
Expected: 1 test file, 1 test, PASS.

- [ ] **Step 7: Verify the app builds and runs**

Run: `npm run build`
Expected: build succeeds with no type or lint errors.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Scaffold Next.js app with Vitest"
```

---

### Task 2: Supabase client setup, migration 1, signup gating test

**Files:**
- Create: `.env.local` (gitignored — confirm it's in `.gitignore`, `create-next-app` includes `.env*.local` by default)
- Create: `.env.local.example`
- Create: `lib/supabase/client.ts`
- Create: `lib/supabase/server.ts`
- Create: `lib/supabase/admin.ts`
- Create: `lib/supabase/types.ts`
- Create: `supabase/migrations/0001_allowed_emails_and_profiles.sql`
- Create: `tests/integration/signup-gating.test.ts`

**Interfaces:**
- Consumes: nothing new
- Produces: `createClient()` (browser, from `lib/supabase/client.ts`), `createClient()` (server, async, from `lib/supabase/server.ts`), `createAdminClient()` (from `lib/supabase/admin.ts`), and the shared types `Profile`, `Trip`, `TripParticipant`, `TripParticipantStatus`, `TripItem`, `TripItemType`, `TripItemConfirmation`, `TripItemConfirmationStatus` from `lib/supabase/types.ts`, used by every later task.

- [ ] **Step 1: Confirm prerequisite — real Supabase keys**

This task cannot be verified until you have the `anon` and `service_role` keys from Project Settings → API. If you don't have them yet, stop here and report back; do not proceed with placeholder keys.

- [ ] **Step 2: Install Supabase packages**

```bash
npm install @supabase/supabase-js @supabase/ssr
```

- [ ] **Step 3: Create env files**

`.env.local.example`:
```
NEXT_PUBLIC_SUPABASE_URL=https://wgsonxheqjvzgfuhbuts.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
```

`.env.local` (real values, never commit):
```
NEXT_PUBLIC_SUPABASE_URL=https://wgsonxheqjvzgfuhbuts.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<real anon key>
SUPABASE_SERVICE_ROLE_KEY=<real service role key>
```

Verify `.gitignore` contains `.env*.local` (it does by default from `create-next-app`).

- [ ] **Step 4: Write shared types**

`lib/supabase/types.ts`:
```ts
export type TripParticipantStatus = 'invited' | 'confirmed' | 'declined';
export type TripItemType = 'hostel' | 'flight' | 'excursion' | 'custom';
export type TripItemConfirmationStatus = 'upvote' | 'in' | 'out';

export interface Profile {
  id: string;
  email: string;
  display_name: string;
  ics_token: string;
  created_at: string;
}

export interface Trip {
  id: string;
  name: string;
  destination_city: string;
  start_date: string;
  end_date: string;
  color: string;
  created_by: string;
  created_at: string;
}

export interface TripParticipant {
  trip_id: string;
  user_id: string;
  status: TripParticipantStatus;
  joined_at: string;
}

export interface TripItem {
  id: string;
  trip_id: string;
  type: TripItemType;
  title: string;
  details: Record<string, unknown>;
  cost: number;
  currency: string;
  proposed_by: string;
  created_at: string;
}

export interface TripItemConfirmation {
  trip_item_id: string;
  user_id: string;
  status: TripItemConfirmationStatus;
  created_at: string;
}
```

- [ ] **Step 5: Write the browser client**

`lib/supabase/client.ts`:
```ts
import { createBrowserClient } from '@supabase/ssr';

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
```

- [ ] **Step 6: Write the server client**

`lib/supabase/server.ts`:
```ts
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // called from a Server Component; middleware refreshes sessions
          }
        },
      },
    }
  );
}
```

- [ ] **Step 7: Write the admin client**

`lib/supabase/admin.ts`:
```ts
import { createClient as createSupabaseClient } from '@supabase/supabase-js';

export function createAdminClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
}
```

- [ ] **Step 8: Write migration 1**

`supabase/migrations/0001_allowed_emails_and_profiles.sql`:
```sql
create extension if not exists pgcrypto;

create table allowed_emails (
  email text primary key,
  added_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  ics_token text not null unique default encode(gen_random_bytes(16), 'hex'),
  created_at timestamptz not null default now()
);

alter table allowed_emails enable row level security;
alter table profiles enable row level security;

create policy "authenticated users can read allowed_emails"
  on allowed_emails for select
  to authenticated
  using (true);

create policy "authenticated users can add allowed_emails"
  on allowed_emails for insert
  to authenticated
  with check (true);

create policy "authenticated users can read all profiles"
  on profiles for select
  to authenticated
  using (true);

create policy "users can update own profile"
  on profiles for update
  to authenticated
  using (id = auth.uid());

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from allowed_emails where email = new.email) then
    raise exception 'Email % is not on the allowed list', new.email;
  end if;

  insert into profiles (id, email, display_name)
  values (new.id, new.email, split_part(new.email, '@', 1));

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

- [ ] **Step 9: Push the migration**

```bash
supabase db push
```

Expected: migration applied with no errors. (Requires the Prerequisites CLI link step to have been done.)

- [ ] **Step 10: Write the failing signup-gating test**

`tests/integration/signup-gating.test.ts`:
```ts
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
```

- [ ] **Step 11: Run the test**

Run: `npm test -- tests/integration/signup-gating.test.ts`
Expected: both tests PASS against the real hosted project.

- [ ] **Step 12: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 13: Commit**

```bash
git add lib/supabase .env.local.example supabase/migrations tests/integration package.json package-lock.json
git commit -m "Add Supabase clients, allowlist/profiles migration, signup gating test"
```

---

### Task 3: Migration 2 — trips + trip_participants

**Files:**
- Create: `supabase/migrations/0002_trips_and_participants.sql`

**Interfaces:**
- Consumes: `profiles` table from Task 2
- Produces: `trips`, `trip_participants` tables; `is_trip_participant(uuid) returns boolean` SQL function, reused by Task 4's policies.

- [ ] **Step 1: Write migration 2**

`supabase/migrations/0002_trips_and_participants.sql`:
```sql
create type trip_participant_status as enum ('invited', 'confirmed', 'declined');

create table trips (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  destination_city text not null,
  start_date date not null,
  end_date date not null,
  color text not null,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  constraint end_after_start check (end_date >= start_date)
);

create table trip_participants (
  trip_id uuid not null references trips(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  status trip_participant_status not null default 'invited',
  joined_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

create or replace function public.is_trip_participant(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from trip_participants
    where trip_id = p_trip_id and user_id = auth.uid()
  );
$$;

alter table trips enable row level security;
alter table trip_participants enable row level security;

create policy "participants can read their trips"
  on trips for select
  to authenticated
  using (is_trip_participant(id));

create policy "authenticated users can create trips"
  on trips for insert
  to authenticated
  with check (created_by = auth.uid());

create policy "participants can read trip_participants rows for their trips"
  on trip_participants for select
  to authenticated
  using (is_trip_participant(trip_id));

create policy "trip creator can invite participants"
  on trip_participants for insert
  to authenticated
  with check (
    user_id = auth.uid()
    or exists (
      select 1 from trips
      where trips.id = trip_participants.trip_id
        and trips.created_by = auth.uid()
    )
  );

create policy "participants can update their own participation status"
  on trip_participants for update
  to authenticated
  using (user_id = auth.uid());
```

- [ ] **Step 2: Push the migration**

Run: `supabase db push`
Expected: applies with no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0002_trips_and_participants.sql
git commit -m "Add trips and trip_participants schema with RLS"
```

---

### Task 4: Migration 3 — trip_items + trip_item_confirmations

**Files:**
- Create: `supabase/migrations/0003_trip_items_and_confirmations.sql`

**Interfaces:**
- Consumes: `trips`, `is_trip_participant()` from Task 3
- Produces: `trip_items`, `trip_item_confirmations` tables, used by Tasks 5–7 and 12–15.

- [ ] **Step 1: Write migration 3**

`supabase/migrations/0003_trip_items_and_confirmations.sql`:
```sql
create type trip_item_type as enum ('hostel', 'flight', 'excursion', 'custom');
create type trip_item_confirmation_status as enum ('upvote', 'in', 'out');

create table trip_items (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references trips(id) on delete cascade,
  type trip_item_type not null,
  title text not null,
  details jsonb not null default '{}'::jsonb,
  cost numeric not null default 0,
  currency text not null default 'USD',
  proposed_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

create table trip_item_confirmations (
  trip_item_id uuid not null references trip_items(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  status trip_item_confirmation_status not null,
  created_at timestamptz not null default now(),
  primary key (trip_item_id, user_id)
);

alter table trip_items enable row level security;
alter table trip_item_confirmations enable row level security;

create policy "participants can read trip_items"
  on trip_items for select
  to authenticated
  using (is_trip_participant(trip_id));

create policy "participants can propose trip_items"
  on trip_items for insert
  to authenticated
  with check (is_trip_participant(trip_id) and proposed_by = auth.uid());

create policy "participants can read confirmations for their trips"
  on trip_item_confirmations for select
  to authenticated
  using (
    exists (
      select 1 from trip_items
      where trip_items.id = trip_item_confirmations.trip_item_id
        and is_trip_participant(trip_items.trip_id)
    )
  );

create policy "participants can set their own confirmation"
  on trip_item_confirmations for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from trip_items
      where trip_items.id = trip_item_confirmations.trip_item_id
        and is_trip_participant(trip_items.trip_id)
    )
  );

create policy "participants can update their own confirmation"
  on trip_item_confirmations for update
  to authenticated
  using (user_id = auth.uid());
```

- [ ] **Step 2: Push the migration**

Run: `supabase db push`
Expected: applies with no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0003_trip_items_and_confirmations.sql
git commit -m "Add trip_items and trip_item_confirmations schema with RLS"
```

---

### Task 5: RLS integration test suite

**Files:**
- Create: `tests/integration/rls.test.ts`

**Interfaces:**
- Consumes: all tables/policies from Tasks 2–4
- Produces: nothing consumed by later tasks — this is a verification-only task.

- [ ] **Step 1: Write the RLS test suite**

`tests/integration/rls.test.ts`:
```ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const admin = createSupabaseClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const userAEmail = `rls-test-a-${Date.now()}@example.com`;
const userBEmail = `rls-test-b-${Date.now()}@example.com`;
const password = 'test-password-12345';

let userAId: string;
let userBId: string;
let tripId: string;

async function signIn(email: string) {
  const client = createSupabaseClient(url, anonKey);
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return client;
}

beforeAll(async () => {
  await admin.from('allowed_emails').insert([{ email: userAEmail }, { email: userBEmail }]);

  const { data: userA } = await admin.auth.admin.createUser({
    email: userAEmail,
    password,
    email_confirm: true,
  });
  const { data: userB } = await admin.auth.admin.createUser({
    email: userBEmail,
    password,
    email_confirm: true,
  });
  userAId = userA.user!.id;
  userBId = userB.user!.id;

  const { data: trip } = await admin
    .from('trips')
    .insert({
      name: 'RLS Test Trip',
      destination_city: 'Testville',
      start_date: '2027-01-01',
      end_date: '2027-01-05',
      color: '#000000',
      created_by: userAId,
    })
    .select()
    .single();
  tripId = trip!.id;

  await admin.from('trip_participants').insert({ trip_id: tripId, user_id: userAId, status: 'confirmed' });
});

afterAll(async () => {
  await admin.auth.admin.deleteUser(userAId);
  await admin.auth.admin.deleteUser(userBId);
  await admin.from('allowed_emails').delete().in('email', [userAEmail, userBEmail]);
});

describe('trip RLS', () => {
  it('lets a participant read their trip', async () => {
    const clientA = await signIn(userAEmail);
    const { data, error } = await clientA.from('trips').select('*').eq('id', tripId);
    expect(error).toBeNull();
    expect(data).toHaveLength(1);
  });

  it('hides the trip from a non-participant', async () => {
    const clientB = await signIn(userBEmail);
    const { data, error } = await clientB.from('trips').select('*').eq('id', tripId);
    expect(error).toBeNull();
    expect(data).toHaveLength(0);
  });

  it('blocks a non-participant from proposing a trip item', async () => {
    const clientB = await signIn(userBEmail);
    const { error } = await clientB
      .from('trip_items')
      .insert({ trip_id: tripId, type: 'custom', title: 'sneaky', cost: 1, proposed_by: userBId });
    expect(error).not.toBeNull();
  });

  it('lets a participant propose a trip item', async () => {
    const clientA = await signIn(userAEmail);
    const { error } = await clientA
      .from('trip_items')
      .insert({ trip_id: tripId, type: 'custom', title: 'legit', cost: 1, proposed_by: userAId });
    expect(error).toBeNull();
  });
});
```

- [ ] **Step 2: Run the suite**

Run: `npm test -- tests/integration/rls.test.ts`
Expected: all 4 tests PASS against the real hosted project.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/rls.test.ts
git commit -m "Add RLS integration test suite"
```

---

### Task 6: `lib/cost-split.ts`

**Files:**
- Create: `lib/cost-split.ts`
- Test: `lib/cost-split.test.ts`

**Interfaces:**
- Consumes: `TripItem`, `TripItemConfirmation` types from Task 2
- Produces: `calculateCostBreakdown(items: TripItem[], confirmations: TripItemConfirmation[]): PersonCost[]`, where `PersonCost = { userId: string; total: number; currency: string }`. Used by Task 14's `CostBreakdown` component.

- [ ] **Step 1: Write the failing tests**

`lib/cost-split.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { calculateCostBreakdown } from './cost-split';
import type { TripItem, TripItemConfirmation } from './supabase/types';

function item(overrides: Partial<TripItem>): TripItem {
  return {
    id: 'i1',
    trip_id: 't1',
    type: 'custom',
    title: 'x',
    details: {},
    cost: 0,
    currency: 'USD',
    proposed_by: 'u1',
    created_at: '',
    ...overrides,
  };
}

function confirmation(overrides: Partial<TripItemConfirmation>): TripItemConfirmation {
  return {
    trip_item_id: 'i1',
    user_id: 'u1',
    status: 'in',
    created_at: '',
    ...overrides,
  };
}

describe('calculateCostBreakdown', () => {
  it('splits an item cost evenly among confirmed users', () => {
    const items = [item({ id: 'i1', cost: 90 })];
    const confirmations = [
      confirmation({ trip_item_id: 'i1', user_id: 'u1' }),
      confirmation({ trip_item_id: 'i1', user_id: 'u2' }),
      confirmation({ trip_item_id: 'i1', user_id: 'u3' }),
    ];

    const result = calculateCostBreakdown(items, confirmations);

    expect(result).toEqual(
      expect.arrayContaining([
        { userId: 'u1', total: 30, currency: 'USD' },
        { userId: 'u2', total: 30, currency: 'USD' },
        { userId: 'u3', total: 30, currency: 'USD' },
      ])
    );
  });

  it('ignores items with no "in" confirmations', () => {
    const items = [item({ id: 'i1', cost: 50 })];
    const confirmations = [confirmation({ trip_item_id: 'i1', user_id: 'u1', status: 'upvote' })];

    expect(calculateCostBreakdown(items, confirmations)).toEqual([]);
  });

  it('sums costs across multiple items for the same person', () => {
    const items = [
      item({ id: 'i1', cost: 100 }),
      item({ id: 'i2', cost: 40 }),
    ];
    const confirmations = [
      confirmation({ trip_item_id: 'i1', user_id: 'u1' }),
      confirmation({ trip_item_id: 'i2', user_id: 'u1' }),
    ];

    expect(calculateCostBreakdown(items, confirmations)).toEqual([
      { userId: 'u1', total: 140, currency: 'USD' },
    ]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- lib/cost-split.test.ts`
Expected: FAIL with "Cannot find module './cost-split'" or similar.

- [ ] **Step 3: Implement**

`lib/cost-split.ts`:
```ts
import type { TripItem, TripItemConfirmation } from './supabase/types';

export interface PersonCost {
  userId: string;
  total: number;
  currency: string;
}

export function calculateCostBreakdown(
  items: TripItem[],
  confirmations: TripItemConfirmation[]
): PersonCost[] {
  const totals = new Map<string, number>();
  let currency = 'USD';

  for (const item of items) {
    currency = item.currency;
    const inUserIds = confirmations
      .filter((c) => c.trip_item_id === item.id && c.status === 'in')
      .map((c) => c.user_id);

    if (inUserIds.length === 0) continue;

    const share = item.cost / inUserIds.length;
    for (const userId of inUserIds) {
      totals.set(userId, (totals.get(userId) ?? 0) + share);
    }
  }

  return Array.from(totals.entries())
    .map(([userId, total]) => ({ userId, total: Math.round(total * 100) / 100, currency }))
    .sort((a, b) => b.total - a.total);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- lib/cost-split.test.ts`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cost-split.ts lib/cost-split.test.ts
git commit -m "Add cost breakdown calculation"
```

---

### Task 7: `lib/ics.ts`

**Files:**
- Create: `lib/ics.ts`
- Test: `lib/ics.test.ts`

**Interfaces:**
- Consumes: `Trip` type from Task 2
- Produces: `generateIcsFeed(trips: Trip[]): string`. Used by Task 16's ICS route.

- [ ] **Step 1: Write the failing tests**

`lib/ics.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { generateIcsFeed } from './ics';
import type { Trip } from './supabase/types';

function trip(overrides: Partial<Trip>): Trip {
  return {
    id: 't1',
    name: 'Barcelona',
    destination_city: 'Barcelona',
    start_date: '2026-10-10',
    end_date: '2026-10-13',
    color: '#000',
    created_by: 'u1',
    created_at: '',
    ...overrides,
  };
}

describe('generateIcsFeed', () => {
  it('produces a valid empty calendar for no trips', () => {
    const ics = generateIcsFeed([]);
    expect(ics).toContain('BEGIN:VCALENDAR');
    expect(ics).toContain('END:VCALENDAR');
    expect(ics).not.toContain('BEGIN:VEVENT');
  });

  it('produces one VEVENT per trip with an exclusive DTEND', () => {
    const ics = generateIcsFeed([trip({})]);
    expect(ics).toContain('BEGIN:VEVENT');
    expect(ics).toContain('SUMMARY:Barcelona');
    expect(ics).toContain('DTSTART;VALUE=DATE:20261010');
    // DTEND is exclusive, so one day after end_date
    expect(ics).toContain('DTEND;VALUE=DATE:20261014');
  });

  it('produces multiple VEVENTs for multiple trips', () => {
    const ics = generateIcsFeed([trip({ id: 't1' }), trip({ id: 't2', name: 'Rome' })]);
    expect(ics.match(/BEGIN:VEVENT/g)).toHaveLength(2);
    expect(ics).toContain('SUMMARY:Rome');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- lib/ics.test.ts`
Expected: FAIL with "Cannot find module './ics'".

- [ ] **Step 3: Implement**

`lib/ics.ts`:
```ts
import type { Trip } from './supabase/types';

function formatIcsDate(dateStr: string): string {
  return dateStr.replace(/-/g, '');
}

function escapeIcsText(text: string): string {
  return text.replace(/([,;])/g, '\\$1');
}

function addDays(dateStr: string, days: number): string {
  const date = new Date(`${dateStr}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function generateIcsFeed(trips: Trip[]): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Trip Planner//EN',
    'CALSCALE:GREGORIAN',
  ];

  for (const trip of trips) {
    lines.push(
      'BEGIN:VEVENT',
      `UID:${trip.id}@trip-planner`,
      `DTSTART;VALUE=DATE:${formatIcsDate(trip.start_date)}`,
      `DTEND;VALUE=DATE:${formatIcsDate(addDays(trip.end_date, 1))}`,
      `SUMMARY:${escapeIcsText(trip.name)}`,
      `LOCATION:${escapeIcsText(trip.destination_city)}`,
      'END:VEVENT'
    );
  }

  lines.push('END:VCALENDAR');
  return lines.join('\r\n');
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- lib/ics.test.ts`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ics.ts lib/ics.test.ts
git commit -m "Add ICS feed generation"
```

---

### Task 8: `lib/calendar-overlap.ts`

**Files:**
- Create: `lib/calendar-overlap.ts`
- Test: `lib/calendar-overlap.test.ts`

**Interfaces:**
- Consumes: `Trip` type from Task 2
- Produces: `findOverlappingTrips(trips: Trip[]): Set<string>` (set of trip ids involved in at least one overlap). Used by Task 15's `CalendarGrid` component.

- [ ] **Step 1: Write the failing tests**

`lib/calendar-overlap.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { findOverlappingTrips } from './calendar-overlap';
import type { Trip } from './supabase/types';

function trip(overrides: Partial<Trip>): Trip {
  return {
    id: 't1',
    name: 'Trip',
    destination_city: 'City',
    start_date: '2026-10-01',
    end_date: '2026-10-05',
    color: '#000',
    created_by: 'u1',
    created_at: '',
    ...overrides,
  };
}

describe('findOverlappingTrips', () => {
  it('flags two trips with overlapping date ranges', () => {
    const trips = [
      trip({ id: 'a', start_date: '2026-10-01', end_date: '2026-10-05' }),
      trip({ id: 'b', start_date: '2026-10-03', end_date: '2026-10-08' }),
    ];
    expect(findOverlappingTrips(trips)).toEqual(new Set(['a', 'b']));
  });

  it('flags trips that share exactly one boundary day', () => {
    const trips = [
      trip({ id: 'a', start_date: '2026-10-01', end_date: '2026-10-05' }),
      trip({ id: 'b', start_date: '2026-10-05', end_date: '2026-10-08' }),
    ];
    expect(findOverlappingTrips(trips)).toEqual(new Set(['a', 'b']));
  });

  it('does not flag disjoint trips', () => {
    const trips = [
      trip({ id: 'a', start_date: '2026-10-01', end_date: '2026-10-05' }),
      trip({ id: 'b', start_date: '2026-10-10', end_date: '2026-10-12' }),
    ];
    expect(findOverlappingTrips(trips)).toEqual(new Set());
  });

  it('only flags the overlapping pair among three trips', () => {
    const trips = [
      trip({ id: 'a', start_date: '2026-10-01', end_date: '2026-10-05' }),
      trip({ id: 'b', start_date: '2026-10-03', end_date: '2026-10-06' }),
      trip({ id: 'c', start_date: '2026-11-01', end_date: '2026-11-05' }),
    ];
    expect(findOverlappingTrips(trips)).toEqual(new Set(['a', 'b']));
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- lib/calendar-overlap.test.ts`
Expected: FAIL with "Cannot find module './calendar-overlap'".

- [ ] **Step 3: Implement**

`lib/calendar-overlap.ts`:
```ts
import type { Trip } from './supabase/types';

function rangesOverlap(aStart: string, aEnd: string, bStart: string, bEnd: string): boolean {
  return aStart <= bEnd && bStart <= aEnd;
}

export function findOverlappingTrips(trips: Trip[]): Set<string> {
  const overlapping = new Set<string>();

  for (let i = 0; i < trips.length; i++) {
    for (let j = i + 1; j < trips.length; j++) {
      if (
        rangesOverlap(
          trips[i].start_date,
          trips[i].end_date,
          trips[j].start_date,
          trips[j].end_date
        )
      ) {
        overlapping.add(trips[i].id);
        overlapping.add(trips[j].id);
      }
    }
  }

  return overlapping;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- lib/calendar-overlap.test.ts`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/calendar-overlap.ts lib/calendar-overlap.test.ts
git commit -m "Add calendar overlap detection"
```

---

### Task 9: Auth flow

**Files:**
- Create: `app/login/page.tsx`
- Create: `app/auth/callback/route.ts`
- Create: `app/logout-action.ts`
- Create: `middleware.ts`

**Interfaces:**
- Consumes: `createClient()` (browser + server) from Task 2
- Produces: `/login` route, `/auth/callback` route, `signOut()` server action (used by Task 11's dashboard nav), session-protecting middleware that all later authenticated routes rely on implicitly.

- [ ] **Step 1: Write the login page**

`app/login/page.tsx`:
```tsx
'use client';

import { useState } from 'react';
import { createClient } from '@/lib/supabase/client';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<'idle' | 'sent' | 'error'>('idle');
  const [error, setError] = useState('');

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
    });
    if (error) {
      setError(error.message);
      setStatus('error');
    } else {
      setStatus('sent');
    }
  }

  if (status === 'sent') {
    return <p className="p-8 text-center">Check your email for a sign-in link.</p>;
  }

  return (
    <form onSubmit={handleSubmit} className="max-w-sm mx-auto mt-24 flex flex-col gap-4 p-4">
      <h1 className="text-xl font-semibold">Sign in</h1>
      <input
        type="email"
        required
        placeholder="you@example.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="border rounded px-3 py-2"
      />
      <button type="submit" className="bg-black text-white rounded px-3 py-2">
        Send magic link
      </button>
      {status === 'error' && <p className="text-red-600 text-sm">{error}</p>}
    </form>
  );
}
```

- [ ] **Step 2: Write the auth callback route**

`app/auth/callback/route.ts`:
```ts
import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get('code');

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return NextResponse.redirect(`${origin}/`);
    }
  }

  return NextResponse.redirect(`${origin}/login?error=auth`);
}
```

- [ ] **Step 3: Write the sign-out server action**

`app/logout-action.ts`:
```ts
'use server';

import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect('/login');
}
```

- [ ] **Step 4: Write the middleware**

`middleware.ts` (project root):
```ts
import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const isAuthRoute = request.nextUrl.pathname.startsWith('/login');
  const isAuthCallback = request.nextUrl.pathname.startsWith('/auth/callback');
  const isIcsRoute = request.nextUrl.pathname.startsWith('/api/ics');

  if (!user && !isAuthRoute && !isAuthCallback && !isIcsRoute) {
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
```

- [ ] **Step 5: Verify the redirect behavior**

Run the dev server in the background, confirm an unauthenticated request to `/` redirects to `/login`, then stop it:
```bash
npm run dev &
sleep 3
curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" http://localhost:3000/
kill %1
```
Expected: a 307/308 status with `redirect_url` ending in `/login`.

- [ ] **Step 6: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 7: Commit**

```bash
git add app/login app/auth app/logout-action.ts middleware.ts
git commit -m "Add magic-link auth flow and route protection middleware"
```

---

### Task 10: Admin allowlist page

**Files:**
- Create: `app/admin/allowed-emails/page.tsx`
- Create: `app/admin/allowed-emails/actions.ts`

**Interfaces:**
- Consumes: `createClient()` (server) from Task 2, auth middleware from Task 9
- Produces: `/admin/allowed-emails` page. Nothing consumed by later tasks.

- [ ] **Step 1: Write the server action**

`app/admin/allowed-emails/actions.ts`:
```ts
'use server';

import { createClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';

export async function addAllowedEmail(formData: FormData) {
  const email = String(formData.get('email') || '').trim().toLowerCase();
  if (!email) return;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase.from('allowed_emails').insert({ email, added_by: user?.id });

  if (error) throw new Error(error.message);

  revalidatePath('/admin/allowed-emails');
}
```

- [ ] **Step 2: Write the page**

`app/admin/allowed-emails/page.tsx`:
```tsx
import { createClient } from '@/lib/supabase/server';
import { addAllowedEmail } from './actions';

export default async function AllowedEmailsPage() {
  const supabase = await createClient();
  const { data: emails } = await supabase
    .from('allowed_emails')
    .select('email, created_at')
    .order('created_at', { ascending: false });

  return (
    <div className="max-w-md mx-auto mt-12 p-4">
      <h1 className="text-xl font-semibold mb-4">Allowed emails</h1>
      <form action={addAllowedEmail} className="flex gap-2 mb-6">
        <input
          type="email"
          name="email"
          required
          placeholder="friend@example.com"
          className="border rounded px-3 py-2 flex-1"
        />
        <button type="submit" className="bg-black text-white rounded px-3 py-2">
          Add
        </button>
      </form>
      <ul className="space-y-1">
        {emails?.map((e) => (
          <li key={e.email} className="text-sm">
            {e.email}
          </li>
        ))}
      </ul>
    </div>
  );
}
```

- [ ] **Step 3: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add app/admin
git commit -m "Add admin allowlist management page"
```

---

### Task 11: Trip creation flow + dashboard

**Files:**
- Create: `lib/palette.ts`
- Create: `app/trips/new/page.tsx`
- Create: `app/trips/new/actions.ts`
- Modify: `app/page.tsx` (replace default Next.js homepage with the trips dashboard)

**Interfaces:**
- Consumes: `createClient()` (server) from Task 2, `Trip`/`TripParticipant` types from Task 2
- Produces: `nextTripColor(existingTripCount: number): string`, `createTrip(formData: FormData)` server action, `/trips/new` page, dashboard at `/`.

- [ ] **Step 1: Write the color palette helper**

`lib/palette.ts`:
```ts
const PALETTE = [
  '#2563eb',
  '#dc2626',
  '#16a34a',
  '#ca8a04',
  '#7c3aed',
  '#db2777',
  '#0891b2',
  '#ea580c',
];

export function nextTripColor(existingTripCount: number): string {
  return PALETTE[existingTripCount % PALETTE.length];
}
```

- [ ] **Step 2: Write the create-trip server action**

`app/trips/new/actions.ts`:
```ts
'use server';

import { createClient } from '@/lib/supabase/server';
import { nextTripColor } from '@/lib/palette';
import { redirect } from 'next/navigation';

export async function createTrip(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  const name = String(formData.get('name'));
  const destination_city = String(formData.get('destination_city'));
  const start_date = String(formData.get('start_date'));
  const end_date = String(formData.get('end_date'));
  const inviteeIds = formData.getAll('invitees').map(String);

  if (end_date < start_date) {
    throw new Error('End date must be on or after the start date.');
  }

  const { count } = await supabase.from('trips').select('id', { count: 'exact', head: true });
  const color = nextTripColor(count ?? 0);

  const { data: trip, error } = await supabase
    .from('trips')
    .insert({ name, destination_city, start_date, end_date, color, created_by: user.id })
    .select()
    .single();

  if (error) throw new Error(error.message);

  const participantRows = [
    { trip_id: trip.id, user_id: user.id, status: 'confirmed' as const },
    ...inviteeIds.map((id) => ({ trip_id: trip.id, user_id: id, status: 'invited' as const })),
  ];

  const { error: participantsError } = await supabase
    .from('trip_participants')
    .insert(participantRows);
  if (participantsError) throw new Error(participantsError.message);

  redirect(`/trips/${trip.id}`);
}
```

- [ ] **Step 3: Write the new-trip page**

`app/trips/new/page.tsx`:
```tsx
import { createClient } from '@/lib/supabase/server';
import { createTrip } from './actions';

export default async function NewTripPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: profiles } = await supabase
    .from('profiles')
    .select('id, display_name, email')
    .neq('id', user!.id);

  return (
    <form action={createTrip} className="max-w-lg mx-auto mt-12 p-4 flex flex-col gap-4">
      <h1 className="text-xl font-semibold">New trip</h1>
      <input name="name" required placeholder="Trip name" className="border rounded px-3 py-2" />
      <input
        name="destination_city"
        required
        placeholder="Destination city"
        className="border rounded px-3 py-2"
      />
      <div className="flex gap-2">
        <input type="date" name="start_date" required className="border rounded px-3 py-2 flex-1" />
        <input type="date" name="end_date" required className="border rounded px-3 py-2 flex-1" />
      </div>
      <fieldset className="border rounded p-3">
        <legend className="text-sm font-medium px-1">Invite</legend>
        {profiles?.map((p) => (
          <label key={p.id} className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="invitees" value={p.id} />
            {p.display_name} ({p.email})
          </label>
        ))}
      </fieldset>
      <button type="submit" className="bg-black text-white rounded px-3 py-2">
        Create trip
      </button>
    </form>
  );
}
```

- [ ] **Step 4: Replace the dashboard homepage**

`app/page.tsx`:
```tsx
import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { signOut } from '@/app/logout-action';

export default async function DashboardPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: participations } = await supabase
    .from('trip_participants')
    .select('status, trips(id, name, destination_city, start_date, end_date, color)')
    .eq('user_id', user!.id);

  return (
    <div className="max-w-2xl mx-auto mt-12 p-4">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-xl font-semibold">Your trips</h1>
        <div className="flex gap-2">
          <Link href="/trips/new" className="bg-black text-white rounded px-3 py-2 text-sm">
            New trip
          </Link>
          <form action={signOut}>
            <button type="submit" className="border rounded px-3 py-2 text-sm">
              Sign out
            </button>
          </form>
        </div>
      </div>
      <ul className="space-y-2">
        {participations?.map((p) => {
          const trip = Array.isArray(p.trips) ? p.trips[0] : p.trips;
          if (!trip) return null;
          return (
            <li key={trip.id} style={{ borderLeftColor: trip.color }} className="border-l-4 pl-3 py-2">
              <Link href={`/trips/${trip.id}`} className="font-medium">
                {trip.name}
              </Link>
              <p className="text-sm text-gray-600">
                {trip.destination_city} · {trip.start_date} – {trip.end_date} · {p.status}
              </p>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
```

- [ ] **Step 5: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add lib/palette.ts app/trips/new app/page.tsx
git commit -m "Add trip creation flow and dashboard"
```

---

### Task 12: Trip detail page — participants

**Files:**
- Create: `app/trips/[id]/page.tsx`
- Create: `app/trips/[id]/actions.ts`
- Create: `components/ParticipantList.tsx`

**Interfaces:**
- Consumes: `createClient()` (server) from Task 2, `TripParticipantStatus` type from Task 2
- Produces: `/trips/[id]` page (participants section); `updateParticipantStatus(tripId: string, formData: FormData)` action; `app/trips/[id]/page.tsx` and `app/trips/[id]/actions.ts` are both extended by Tasks 13 and 14.

- [ ] **Step 1: Write the participant-status action**

`app/trips/[id]/actions.ts`:
```ts
'use server';

import { createClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';
import type { TripParticipantStatus } from '@/lib/supabase/types';

export async function updateParticipantStatus(tripId: string, formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const status = String(formData.get('status')) as TripParticipantStatus;

  const { error } = await supabase
    .from('trip_participants')
    .update({ status })
    .eq('trip_id', tripId)
    .eq('user_id', user!.id);

  if (error) throw new Error(error.message);
  revalidatePath(`/trips/${tripId}`);
}
```

- [ ] **Step 2: Write the ParticipantList component**

`components/ParticipantList.tsx`:
```tsx
'use client';

import { updateParticipantStatus } from '@/app/trips/[id]/actions';
import type { TripParticipantStatus } from '@/lib/supabase/types';

interface Participant {
  user_id: string;
  status: TripParticipantStatus;
  display_name: string;
}

export function ParticipantList({
  tripId,
  participants,
  currentUserId,
}: {
  tripId: string;
  participants: Participant[];
  currentUserId: string;
}) {
  return (
    <ul className="space-y-1">
      {participants.map((p) => (
        <li key={p.user_id} className="flex items-center justify-between text-sm">
          <span>{p.display_name}</span>
          {p.user_id === currentUserId ? (
            <form action={updateParticipantStatus.bind(null, tripId)}>
              <select
                name="status"
                defaultValue={p.status}
                onChange={(e) => e.currentTarget.form?.requestSubmit()}
                className="border rounded px-2 py-1"
              >
                <option value="invited">Invited</option>
                <option value="confirmed">Confirmed</option>
                <option value="declined">Declined</option>
              </select>
            </form>
          ) : (
            <span className="text-gray-500">{p.status}</span>
          )}
        </li>
      ))}
    </ul>
  );
}
```

- [ ] **Step 3: Write the trip detail page**

`app/trips/[id]/page.tsx`:
```tsx
import { createClient } from '@/lib/supabase/server';
import { ParticipantList } from '@/components/ParticipantList';

export default async function TripDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: trip } = await supabase.from('trips').select('*').eq('id', id).single();
  const { data: participantRows } = await supabase
    .from('trip_participants')
    .select('user_id, status, profiles(display_name)')
    .eq('trip_id', id);

  const participants = (participantRows ?? []).map((p) => {
    const profile = Array.isArray(p.profiles) ? p.profiles[0] : p.profiles;
    return {
      user_id: p.user_id,
      status: p.status,
      display_name: profile?.display_name ?? 'Unknown',
    };
  });

  return (
    <div className="max-w-2xl mx-auto mt-12 p-4">
      <h1 className="text-xl font-semibold" style={{ color: trip?.color }}>
        {trip?.name}
      </h1>
      <p className="text-sm text-gray-600 mb-6">
        {trip?.destination_city} · {trip?.start_date} – {trip?.end_date}
      </p>
      <h2 className="font-medium mb-2">Participants</h2>
      <ParticipantList tripId={id} participants={participants} currentUserId={user!.id} />
    </div>
  );
}
```

- [ ] **Step 4: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add app/trips/[id] components/ParticipantList.tsx
git commit -m "Add trip detail page with participant list"
```

---

### Task 13: Propose item flow

**Files:**
- Modify: `app/trips/[id]/actions.ts` (add `proposeItem`)
- Modify: `app/trips/[id]/page.tsx` (fetch and render trip_items)
- Create: `components/ProposeItemForm.tsx`
- Create: `components/TripItemCard.tsx`

**Interfaces:**
- Consumes: `TripItem`, `TripItemType` types from Task 2, page/actions files from Task 12
- Produces: `proposeItem(tripId: string, formData: FormData)` action; `components/TripItemCard.tsx` is extended again in Task 14 to add confirmation buttons.

- [ ] **Step 1: Add the propose-item action**

Append to `app/trips/[id]/actions.ts`:
```ts
export async function proposeItem(tripId: string, formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase.from('trip_items').insert({
    trip_id: tripId,
    type: String(formData.get('type')),
    title: String(formData.get('title')),
    cost: Number(formData.get('cost')),
    currency: String(formData.get('currency') || 'USD'),
    proposed_by: user!.id,
  });

  if (error) throw new Error(error.message);
  revalidatePath(`/trips/${tripId}`);
}
```

- [ ] **Step 2: Write the ProposeItemForm component**

`components/ProposeItemForm.tsx`:
```tsx
'use client';

import { proposeItem } from '@/app/trips/[id]/actions';

export function ProposeItemForm({ tripId }: { tripId: string }) {
  return (
    <form
      action={proposeItem.bind(null, tripId)}
      className="border rounded p-3 flex flex-col gap-2 mt-4"
    >
      <h3 className="font-medium text-sm">Propose an item</h3>
      <select name="type" className="border rounded px-2 py-1 text-sm">
        <option value="hostel">Hostel</option>
        <option value="flight">Flight</option>
        <option value="excursion">Excursion</option>
        <option value="custom">Custom</option>
      </select>
      <input name="title" required placeholder="Title" className="border rounded px-2 py-1 text-sm" />
      <div className="flex gap-2">
        <input
          name="cost"
          type="number"
          step="0.01"
          required
          placeholder="Cost"
          className="border rounded px-2 py-1 text-sm flex-1"
        />
        <input name="currency" defaultValue="USD" className="border rounded px-2 py-1 text-sm w-20" />
      </div>
      <button type="submit" className="bg-black text-white rounded px-3 py-2 text-sm">
        Propose
      </button>
    </form>
  );
}
```

- [ ] **Step 3: Write the TripItemCard component**

`components/TripItemCard.tsx`:
```tsx
import type { TripItem } from '@/lib/supabase/types';

export function TripItemCard({ item, proposerName }: { item: TripItem; proposerName: string }) {
  return (
    <li className="border rounded p-3">
      <div className="flex justify-between text-sm">
        <span className="font-medium">{item.title}</span>
        <span>
          {item.cost} {item.currency}
        </span>
      </div>
      <p className="text-xs text-gray-500">
        {item.type} · proposed by {proposerName}
      </p>
    </li>
  );
}
```

- [ ] **Step 4: Update the trip detail page to render items**

Modify `app/trips/[id]/page.tsx` — add imports and a new section after the participants section:

```tsx
import { createClient } from '@/lib/supabase/server';
import { ParticipantList } from '@/components/ParticipantList';
import { ProposeItemForm } from '@/components/ProposeItemForm';
import { TripItemCard } from '@/components/TripItemCard';

export default async function TripDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: trip } = await supabase.from('trips').select('*').eq('id', id).single();
  const { data: participantRows } = await supabase
    .from('trip_participants')
    .select('user_id, status, profiles(display_name)')
    .eq('trip_id', id);
  const { data: itemRows } = await supabase
    .from('trip_items')
    .select('*, profiles(display_name)')
    .eq('trip_id', id)
    .order('created_at');

  const participants = (participantRows ?? []).map((p) => {
    const profile = Array.isArray(p.profiles) ? p.profiles[0] : p.profiles;
    return {
      user_id: p.user_id,
      status: p.status,
      display_name: profile?.display_name ?? 'Unknown',
    };
  });

  return (
    <div className="max-w-2xl mx-auto mt-12 p-4">
      <h1 className="text-xl font-semibold" style={{ color: trip?.color }}>
        {trip?.name}
      </h1>
      <p className="text-sm text-gray-600 mb-6">
        {trip?.destination_city} · {trip?.start_date} – {trip?.end_date}
      </p>
      <h2 className="font-medium mb-2">Participants</h2>
      <ParticipantList tripId={id} participants={participants} currentUserId={user!.id} />

      <h2 className="font-medium mt-6 mb-2">Proposed items</h2>
      <ul className="space-y-2">
        {itemRows?.map((item) => {
          const profile = Array.isArray(item.profiles) ? item.profiles[0] : item.profiles;
          return (
            <TripItemCard key={item.id} item={item} proposerName={profile?.display_name ?? 'Unknown'} />
          );
        })}
      </ul>
      <ProposeItemForm tripId={id} />
    </div>
  );
}
```

- [ ] **Step 5: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add app/trips/[id] components/ProposeItemForm.tsx components/TripItemCard.tsx
git commit -m "Add propose-item flow to trip detail page"
```

---

### Task 14: Confirm item + cost breakdown

**Files:**
- Modify: `app/trips/[id]/actions.ts` (add `setConfirmation`)
- Modify: `app/trips/[id]/page.tsx` (fetch confirmations, render CostBreakdown)
- Modify: `components/TripItemCard.tsx` (add confirm buttons)
- Create: `components/CostBreakdown.tsx`

**Interfaces:**
- Consumes: `calculateCostBreakdown` from Task 6, `TripItemConfirmation`/`TripItemConfirmationStatus` types from Task 2
- Produces: `setConfirmation(tripItemId: string, formData: FormData)` action; `components/CostBreakdown.tsx`. Nothing consumed by later tasks.

- [ ] **Step 1: Add the confirmation action**

Append to `app/trips/[id]/actions.ts`:
```ts
export async function setConfirmation(tripItemId: string, formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const status = String(formData.get('status'));

  const { error } = await supabase
    .from('trip_item_confirmations')
    .upsert(
      { trip_item_id: tripItemId, user_id: user!.id, status },
      { onConflict: 'trip_item_id,user_id' }
    );

  if (error) throw new Error(error.message);

  const { data: item } = await supabase
    .from('trip_items')
    .select('trip_id')
    .eq('id', tripItemId)
    .single();
  if (item) revalidatePath(`/trips/${item.trip_id}`);
}
```

- [ ] **Step 2: Update TripItemCard with confirm buttons**

Replace `components/TripItemCard.tsx`:
```tsx
import type { TripItem, TripItemConfirmation } from '@/lib/supabase/types';
import { setConfirmation } from '@/app/trips/[id]/actions';

export function TripItemCard({
  item,
  proposerName,
  confirmations,
  currentUserId,
}: {
  item: TripItem;
  proposerName: string;
  confirmations: TripItemConfirmation[];
  currentUserId: string;
}) {
  const mine = confirmations.find((c) => c.user_id === currentUserId);
  const inCount = confirmations.filter((c) => c.status === 'in').length;

  return (
    <li className="border rounded p-3">
      <div className="flex justify-between text-sm">
        <span className="font-medium">{item.title}</span>
        <span>
          {item.cost} {item.currency}
        </span>
      </div>
      <p className="text-xs text-gray-500 mb-2">
        {item.type} · proposed by {proposerName} · {inCount} in
      </p>
      <form action={setConfirmation.bind(null, item.id)} className="flex gap-2">
        {(['upvote', 'in', 'out'] as const).map((status) => (
          <button
            key={status}
            type="submit"
            name="status"
            value={status}
            className={`text-xs border rounded px-2 py-1 ${
              mine?.status === status ? 'bg-black text-white' : ''
            }`}
          >
            {status}
          </button>
        ))}
      </form>
    </li>
  );
}
```

- [ ] **Step 3: Write the CostBreakdown component**

`components/CostBreakdown.tsx`:
```tsx
import { calculateCostBreakdown } from '@/lib/cost-split';
import type { TripItem, TripItemConfirmation } from '@/lib/supabase/types';

export function CostBreakdown({
  items,
  confirmations,
  names,
}: {
  items: TripItem[];
  confirmations: TripItemConfirmation[];
  names: Record<string, string>;
}) {
  const breakdown = calculateCostBreakdown(items, confirmations);

  if (breakdown.length === 0) {
    return <p className="text-sm text-gray-500">No confirmed costs yet.</p>;
  }

  return (
    <ul className="text-sm space-y-1">
      {breakdown.map((b) => (
        <li key={b.userId} className="flex justify-between">
          <span>{names[b.userId] ?? b.userId}</span>
          <span>
            {b.total.toFixed(2)} {b.currency}
          </span>
        </li>
      ))}
    </ul>
  );
}
```

- [ ] **Step 4: Wire it all up in the trip detail page**

Replace `app/trips/[id]/page.tsx`:
```tsx
import { createClient } from '@/lib/supabase/server';
import { ParticipantList } from '@/components/ParticipantList';
import { ProposeItemForm } from '@/components/ProposeItemForm';
import { TripItemCard } from '@/components/TripItemCard';
import { CostBreakdown } from '@/components/CostBreakdown';

export default async function TripDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: trip } = await supabase.from('trips').select('*').eq('id', id).single();
  const { data: participantRows } = await supabase
    .from('trip_participants')
    .select('user_id, status, profiles(display_name)')
    .eq('trip_id', id);
  const { data: itemRows } = await supabase
    .from('trip_items')
    .select('*, profiles(display_name)')
    .eq('trip_id', id)
    .order('created_at');
  const itemIds = (itemRows ?? []).map((i) => i.id);
  const { data: confirmationRows } = itemIds.length
    ? await supabase.from('trip_item_confirmations').select('*').in('trip_item_id', itemIds)
    : { data: [] };

  const participants = (participantRows ?? []).map((p) => {
    const profile = Array.isArray(p.profiles) ? p.profiles[0] : p.profiles;
    return {
      user_id: p.user_id,
      status: p.status,
      display_name: profile?.display_name ?? 'Unknown',
    };
  });

  const names = Object.fromEntries(participants.map((p) => [p.user_id, p.display_name]));
  const items = itemRows ?? [];
  const confirmations = confirmationRows ?? [];

  return (
    <div className="max-w-2xl mx-auto mt-12 p-4">
      <h1 className="text-xl font-semibold" style={{ color: trip?.color }}>
        {trip?.name}
      </h1>
      <p className="text-sm text-gray-600 mb-6">
        {trip?.destination_city} · {trip?.start_date} – {trip?.end_date}
      </p>
      <h2 className="font-medium mb-2">Participants</h2>
      <ParticipantList tripId={id} participants={participants} currentUserId={user!.id} />

      <h2 className="font-medium mt-6 mb-2">Proposed items</h2>
      <ul className="space-y-2">
        {items.map((item) => {
          const profile = Array.isArray(item.profiles) ? item.profiles[0] : item.profiles;
          return (
            <TripItemCard
              key={item.id}
              item={item}
              proposerName={profile?.display_name ?? 'Unknown'}
              confirmations={confirmations.filter((c) => c.trip_item_id === item.id)}
              currentUserId={user!.id}
            />
          );
        })}
      </ul>
      <ProposeItemForm tripId={id} />

      <h2 className="font-medium mt-6 mb-2">Cost breakdown</h2>
      <CostBreakdown items={items} confirmations={confirmations} names={names} />
    </div>
  );
}
```

- [ ] **Step 5: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add app/trips/[id] components/TripItemCard.tsx components/CostBreakdown.tsx
git commit -m "Add item confirmation and per-person cost breakdown"
```

---

### Task 15: Shared calendar page

**Files:**
- Create: `components/CalendarGrid.tsx`
- Create: `app/calendar/page.tsx`

**Interfaces:**
- Consumes: `findOverlappingTrips` from Task 8, `Trip` type from Task 2
- Produces: `/calendar` page. Nothing consumed by later tasks.

- [ ] **Step 1: Install date-fns**

```bash
npm install date-fns
```

- [ ] **Step 2: Write the CalendarGrid component**

`components/CalendarGrid.tsx`:
```tsx
import {
  eachDayOfInterval,
  startOfMonth,
  endOfMonth,
  startOfWeek,
  endOfWeek,
  format,
  isSameMonth,
} from 'date-fns';
import type { Trip } from '@/lib/supabase/types';
import { findOverlappingTrips } from '@/lib/calendar-overlap';

export function CalendarGrid({ month, trips }: { month: Date; trips: Trip[] }) {
  const start = startOfWeek(startOfMonth(month));
  const end = endOfWeek(endOfMonth(month));
  const days = eachDayOfInterval({ start, end });
  const overlapping = findOverlappingTrips(trips);

  function tripsOnDay(day: Date) {
    const iso = format(day, 'yyyy-MM-dd');
    return trips.filter((t) => t.start_date <= iso && iso <= t.end_date);
  }

  return (
    <div className="grid grid-cols-7 gap-1">
      {days.map((day) => {
        const dayTrips = tripsOnDay(day);
        return (
          <div
            key={day.toISOString()}
            className={`border rounded p-1 min-h-20 text-xs ${
              isSameMonth(day, month) ? '' : 'opacity-40'
            }`}
          >
            <div className="text-right">{format(day, 'd')}</div>
            {dayTrips.map((t) => (
              <div
                key={t.id}
                style={{ backgroundColor: t.color }}
                className="text-white rounded px-1 mt-0.5 truncate"
                title={overlapping.has(t.id) ? `${t.name} (overlaps another trip)` : t.name}
              >
                {t.name}
                {overlapping.has(t.id) ? ' ⚠' : ''}
              </div>
            ))}
          </div>
        );
      })}
    </div>
  );
}
```

- [ ] **Step 3: Write the calendar page**

`app/calendar/page.tsx`:
```tsx
import { createClient } from '@/lib/supabase/server';
import { CalendarGrid } from '@/components/CalendarGrid';

export default async function CalendarPage() {
  const supabase = await createClient();
  const { data: trips } = await supabase.from('trips').select('*').order('start_date');

  return (
    <div className="max-w-3xl mx-auto mt-12 p-4">
      <h1 className="text-xl font-semibold mb-4">Group calendar</h1>
      <CalendarGrid month={new Date()} trips={trips ?? []} />
    </div>
  );
}
```

- [ ] **Step 4: Run the full build**

Run: `npm run build`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json components/CalendarGrid.tsx app/calendar
git commit -m "Add shared calendar view with overlap flagging"
```

---

### Task 16: ICS feed route

**Files:**
- Create: `app/api/ics/[token]/route.ts`

**Interfaces:**
- Consumes: `createAdminClient()` from Task 2, `generateIcsFeed` from Task 7
- Produces: `/api/ics/[token]` route. Nothing consumed by later tasks.

- [ ] **Step 1: Write the route**

`app/api/ics/[token]/route.ts`:
```ts
import { NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/admin';
import { generateIcsFeed } from '@/lib/ics';

export async function GET(_request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const supabase = createAdminClient();

  const { data: profile } = await supabase
    .from('profiles')
    .select('id')
    .eq('ics_token', token)
    .single();

  if (!profile) {
    return new NextResponse('Not found', { status: 404 });
  }

  const { data: trips } = await supabase.from('trips').select('*').order('start_date');

  return new NextResponse(generateIcsFeed(trips ?? []), {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': 'inline; filename="trips.ics"',
    },
  });
}
```

- [ ] **Step 2: Verify with a real token**

Get a real `ics_token` and confirm the feed responds correctly, then confirm a bad token 404s:
```bash
npm run dev &
sleep 3
TOKEN=$(node -e "
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config({ path: '.env.local' });
const c = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
c.from('profiles').select('ics_token').limit(1).single().then(({ data }) => console.log(data.ics_token));
")
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/api/ics/$TOKEN"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/api/ics/not-a-real-token"
kill %1
```
Expected: first curl prints `200`, second prints `404`. (Requires at least one real profile row to exist — one will exist from Task 2's or Task 5's test runs if not cleaned up, or sign in once via `/login` first.)

- [ ] **Step 3: Commit**

```bash
git add app/api/ics
git commit -m "Add per-user ICS calendar feed"
```

---

### Task 17: Manual end-to-end verification

**Files:** none — this task is a manual browser walkthrough, not code.

**Interfaces:**
- Consumes: the entire app built in Tasks 1–16.

- [ ] **Step 1: Seed two allowlisted emails**

Run `npm run dev`, visit `/admin/allowed-emails` (you'll be redirected to `/login` first — sign in with any allowlisted email you've already created via the Task 2/5 test scripts, or manually insert your own real email into `allowed_emails` via the Supabase SQL editor first). Add a second real email you can access (e.g. a personal alias) so you can test multi-person confirmation.

- [ ] **Step 2: Sign in as both users**

In two separate browsers (or one regular + one incognito window), sign in via `/login` with each email's magic link.

- [ ] **Step 3: Create a trip and invite the second user**

As user 1, go to `/trips/new`, create a trip, check the box to invite user 2, submit. Confirm you land on `/trips/[id]` and see yourself listed as "confirmed" and user 2 as "invited".

- [ ] **Step 4: Confirm as the invitee**

As user 2, navigate to the dashboard (`/`), confirm the trip appears with status "invited", open it, and change your status to "confirmed" via the dropdown.

- [ ] **Step 5: Propose and confirm an item**

As user 1, propose an item (e.g. type "hostel", title "Test Hostel", cost 100). As user 2, mark yourself "in" on it. As user 1, also mark yourself "in". Confirm the cost breakdown panel shows 50 for each user.

- [ ] **Step 6: Check the calendar**

Visit `/calendar` as either user. Confirm the trip appears as a colored bar on the correct dates. Create a second trip with overlapping dates and confirm both trips show the overlap warning (⚠).

- [ ] **Step 7: Check the ICS feed**

As user 1, find your `ics_token` (via the Supabase table editor on `profiles`, since there's no UI for it yet) and visit `/api/ics/<token>` directly in the browser. Confirm it downloads/displays a valid `.ics` file listing both trips.

- [ ] **Step 8: Report results**

If every step above worked, phase 1 is complete. If anything failed, note which step and what happened — do not mark this task done until all 7 steps pass.
