create extension if not exists pgcrypto with schema extensions;

create table allowed_emails (
  email text primary key,
  added_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  ics_token text not null unique default encode(extensions.gen_random_bytes(16), 'hex'),
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
