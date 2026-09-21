-- Fix 1: trip_participants INSERT policy allowed self-join to any trip.
-- Restrict INSERT to the trip creator only.
drop policy "trip creator can invite participants" on trip_participants;

create policy "trip creator can invite participants"
  on trip_participants for insert
  to authenticated
  with check (
    exists (
      select 1 from trips
      where trips.id = trip_participants.trip_id
        and trips.created_by = auth.uid()
    )
  );

-- Fix 2: trip_participants UPDATE policy allowed re-parenting a row to a
-- different trip_id, since RLS's WITH CHECK cannot reference the OLD row.
-- Enforce with a trigger instead.
create or replace function public.prevent_trip_participant_reparenting()
returns trigger
language plpgsql
as $$
begin
  if new.trip_id <> old.trip_id then
    raise exception 'trip_id cannot be changed on an existing trip_participants row';
  end if;
  return new;
end;
$$;

create trigger trip_participants_no_reparenting
  before update on trip_participants
  for each row execute function public.prevent_trip_participant_reparenting();
