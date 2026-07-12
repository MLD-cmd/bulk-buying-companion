create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hubs (
  id text primary key,
  name text not null,
  type text not null check (type in ('dormitory', 'area_hub')),
  distance_label text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.hub_memberships (
  user_id uuid primary key references auth.users (id) on delete cascade,
  hub_id text not null references public.hubs (id) on delete cascade,
  joined_at timestamptz not null default now()
);

create index if not exists hub_memberships_hub_id_idx
  on public.hub_memberships (hub_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    nullif(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (user_id) do update
  set
    email = excluded.email,
    display_name = excluded.display_name,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.hubs enable row level security;
alter table public.hub_memberships enable row level security;

grant select, update on public.profiles to authenticated;
grant select on public.hubs to authenticated;
grant select, insert, update, delete on public.hub_memberships to authenticated;

drop policy if exists "profiles select own row" on public.profiles;
create policy "profiles select own row"
on public.profiles
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "profiles update own row" on public.profiles;
create policy "profiles update own row"
on public.profiles
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "hubs select authenticated" on public.hubs;
create policy "hubs select authenticated"
on public.hubs
for select
to authenticated
using (true);

drop policy if exists "hub memberships select own row" on public.hub_memberships;
create policy "hub memberships select own row"
on public.hub_memberships
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "hub memberships insert own row" on public.hub_memberships;
create policy "hub memberships insert own row"
on public.hub_memberships
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "hub memberships update own row" on public.hub_memberships;
create policy "hub memberships update own row"
on public.hub_memberships
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "hub memberships delete own row" on public.hub_memberships;
create policy "hub memberships delete own row"
on public.hub_memberships
for delete
to authenticated
using (user_id = (select auth.uid()));

create or replace view public.hub_directory as
select
  hubs.id,
  hubs.name,
  hubs.type,
  hubs.distance_label,
  count(hub_memberships.user_id)::bigint as member_count
from public.hubs
left join public.hub_memberships on hub_memberships.hub_id = hubs.id
group by hubs.id, hubs.name, hubs.type, hubs.distance_label;

grant select on public.hub_directory to authenticated;

insert into public.hubs (id, name, type, distance_label)
values
  ('magallanes', 'Magallanes Residence', 'dormitory', '150 m'),
  ('burgos', 'P. Burgos Boarding House', 'dormitory', '300 m'),
  ('colon', 'Colon Street Hub', 'area_hub', '400 m'),
  ('sanciangko', 'Sanciangko Apartments', 'dormitory', '600 m'),
  ('junquera', 'Junquera Area Hub', 'area_hub', '850 m')
on conflict (id) do update
set
  name = excluded.name,
  type = excluded.type,
  distance_label = excluded.distance_label;
