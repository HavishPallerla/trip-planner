# Trip Planner — Phase 1: Coordination Core

**Date:** 2026-09-21
**Status:** Approved, ready for implementation planning

## Context

A group of ~10 friends studying abroad wants to coordinate trips to the
same destinations at the same times. The full product vision includes
searching hostels (Hostelworld), flights (Skyscanner), and excursions
(Viator/GetYourGuide), plus shared trip planning and a shared calendar.

This is too large for one implementation pass. This spec covers only
**Phase 1: the coordination core** — trip creation, shared calendar,
and manual (non-API) proposal/confirmation/cost-breakdown. Later
phases (flights, hostels, excursions) plug into the data model built
here without changing it.

**Phase order (whole project):**
1. Coordination core (this spec): auth, roster, trips, calendar, manual
   item proposals, confirmations, cost breakdown, ICS export.
2. Flights search (Skyscanner) — replaces manual entry for `type: flight`
   items with a real search-and-propose flow.
3. Hostels search (Hostelworld) — same pattern for `type: hostel`.
4. Excursions search (Viator/GetYourGuide) — same pattern for `type: excursion`.

## Goals (Phase 1)

- Closed group of ~10 people can sign in via magic link.
- Anyone can create a trip and invite others from the group.
- Anyone can propose a trip item (hostel/flight/excursion/custom) by
  manually entering title + cost; others can upvote / mark "I'm in".
- Per-trip view shows per-person cost breakdown and who's confirmed
  for what.
- A shared calendar shows all trips across the group, color-coded,
  with overlapping trips visually flagged.
- Each person can subscribe to a personal ICS feed reflecting all
  group trips in their own calendar app.

## Non-goals (Phase 1)

- No Hostelworld/Skyscanner/Viator/GetYourGuide API integration.
- No two-way Google Calendar OAuth sync — ICS feed (one-way) only.
- No native mobile app — responsive web only.
- No payment settlement/splitting beyond displaying the breakdown.
- No multi-group support — one fixed friend group per deployment.

## Tech stack

- **Framework:** Next.js (App Router, TypeScript), Tailwind CSS.
- **Backend:** Supabase (Postgres, Auth, Row Level Security).
- **Auth:** Supabase magic-link (email OTP) sign-in.
- **Hosting target:** Vercel (not deployed as part of this phase).

### Repo layout

```
trip-planner/
  app/                    # Next.js routes
    trips/[id]/           # trip detail page
    calendar/             # shared calendar view
    api/ics/[token]/      # ICS feed endpoint
  components/
  lib/
    supabase/             # client + generated types
    ics.ts                # ICS feed generation (pure function)
    cost-split.ts          # cost breakdown calculation (pure function)
  supabase/
    migrations/           # SQL schema + RLS policies
  docs/superpowers/specs/
```

## Data model

All tables live in Supabase Postgres, RLS-protected.

### `allowed_emails`
Admin-managed allowlist gating signup.
- `email` (text, primary key)
- `added_by` (uuid, references profiles)
- `created_at`

A Postgres trigger on `auth.users` insert only allows the row (and the
corresponding `profiles` row creation) to proceed if the signing-up
email exists in `allowed_emails`; otherwise the signup is rejected.

### `profiles`
The roster — one row per group member.
- `id` (uuid, = `auth.users.id`, primary key)
- `email` (text)
- `display_name` (text)
- `ics_token` (text, unique, generated on creation) — used to
  authenticate the personal ICS feed URL without requiring login.
- `created_at`

RLS: readable by any authenticated user (single shared group, no
internal privacy boundary).

### `trips`
- `id` (uuid, primary key)
- `name` (text)
- `destination_city` (text)
- `start_date`, `end_date` (date)
- `color` (text) — assigned from a fixed palette at creation time
- `created_by` (uuid, references profiles)
- `created_at`

RLS: readable/writable only by rows present in `trip_participants` for
that trip.

### `trip_participants`
- `trip_id` (uuid, references trips)
- `user_id` (uuid, references profiles)
- `status` (enum: `invited`, `confirmed`, `declined`)
- `joined_at`
- Primary key: (`trip_id`, `user_id`)

### `trip_items`
A proposed hostel/flight/excursion/custom item within a trip.
- `id` (uuid, primary key)
- `trip_id` (uuid, references trips)
- `type` (enum: `hostel`, `flight`, `excursion`, `custom`)
- `title` (text)
- `details` (jsonb) — free-form, type-specific fields. Phase 1 leaves
  this mostly empty (title/cost carry the info); later phases populate
  it with structured data from the relevant search API (e.g. flight
  number, departure time, provider link).
- `cost` (numeric)
- `currency` (text, default `USD`)
- `proposed_by` (uuid, references profiles)
- `created_at`

RLS: readable/writable only by trip participants.

### `trip_item_confirmations`
- `trip_item_id` (uuid, references trip_items)
- `user_id` (uuid, references profiles)
- `status` (enum: `upvote`, `in`, `out`)
- `created_at`
- Primary key: (`trip_item_id`, `user_id`)

## Core flows

### Auth & roster
1. Admin adds the ~10 friends' emails to `allowed_emails` (a simple
   admin page: enter email, insert row — no complex UI needed for 10
   people).
2. Each friend visits the app, enters their email, gets a magic link.
   On first successful login, the `auth.users` trigger creates their
   `profiles` row (rejected if email isn't allowlisted).

### Trip creation
1. "New Trip" form: name, destination city (free text), start/end
   date, invite participants (multi-select from `profiles`).
2. On submit: insert `trips` row (color auto-assigned round-robin from
   a fixed palette), insert `trip_participants` rows for the creator
   (`confirmed`) and invitees (`invited`).
3. Invitees see the trip on their dashboard and can confirm/decline.

### Proposing & confirming items
1. On a trip detail page, "Propose an item" opens a form: type
   (dropdown), title, cost, currency.
2. Each item displayed shows proposer, cost, and a row of
   participants who've upvoted/marked themselves "in".
3. Any trip participant can toggle their own confirmation status on
   any item.
4. Cost breakdown panel: for each item with at least one `in`
   confirmation, cost ÷ number of `in` participants; summed per person
   across all items in the trip. Pure calculation function in
   `lib/cost-split.ts`, unit-tested directly.

### Shared calendar
1. `/calendar` renders a month/week grid of all trips (all trips are
   visible to all group members — the point is overlap-awareness).
2. Each trip renders as a colored bar spanning `start_date`–`end_date`.
3. Overlapping trip date ranges are visually flagged (e.g. stacked
   with a warning badge) — pure date-range overlap detection, unit
   tested.
4. Each user has a stable ICS feed URL at `/api/ics/[token]` (token =
   their `profiles.ics_token`). The endpoint returns a `text/calendar`
   document listing all trips as VEVENTs. Users subscribe to this URL
   in Google/Apple Calendar. Generation logic lives in `lib/ics.ts` as
   a pure function taking trips and returning ICS text, unit-tested
   separately from the route handler.

## Error handling

- Signup with a non-allowlisted email: reject at the trigger level;
  UI shows "This app is invite-only — ask a friend to add your email."
- Trip creation with end date before start date: client + server-side
  validation, reject with inline error.
- Confirming an item / trip you're not a participant of: blocked by
  RLS; UI simply won't expose the action.
- ICS feed with invalid/unknown token: 404.

## Testing plan

- Unit tests for `lib/cost-split.ts` (even-split calculation across
  various confirmation combinations) and `lib/ics.ts` (ICS output
  shape for one trip, multiple trips, empty list).
- Unit tests for calendar overlap detection.
- SQL/RLS policy checks: a non-participant cannot read/write a trip's
  `trip_items`/`trip_participants`; a non-allowlisted email cannot
  create a `profiles` row.
- Manual click-through in-browser: sign in via magic link, create a
  trip, invite a second (test) account, propose an item, confirm it,
  verify cost breakdown, verify the trip appears on `/calendar`,
  verify the ICS feed URL returns valid calendar data.
