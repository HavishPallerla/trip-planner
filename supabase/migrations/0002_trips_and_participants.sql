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
