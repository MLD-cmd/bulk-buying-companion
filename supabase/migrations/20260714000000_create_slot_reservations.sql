-- One row per student per deal. The composite primary key IS the rule
-- "prevent duplicate reservations" -- enforced by Postgres rather than by
-- application code that has to remember to check on every path.
create table if not exists public.deal_reservations (
  deal_id uuid not null references public.deals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  reserved_at timestamptz not null default now(),
  primary key (deal_id, user_id)
);

create index if not exists deal_reservations_user_id_idx
  on public.deal_reservations (user_id);

alter table public.deal_reservations enable row level security;

-- A student may see who else is in a deal posted to a hub they belong to.
drop policy if exists "deal reservations select in own hub" on public.deal_reservations;
create policy "deal reservations select in own hub"
on public.deal_reservations
for select
to authenticated
using (
  exists (
    select 1
    from public.deals d
    join public.hub_memberships m on m.hub_id = d.hub_id
    where d.id = deal_reservations.deal_id
      and m.user_id = (select auth.uid())
  )
);

-- Deliberately NO insert/update/delete policies. Every mutation goes through
-- the security-definer functions below, because a reservation written without
-- the matching decrement of available_slots would desynchronise the two.

-- available_slots is a denormalised counter, and a denormalised counter that
-- anything can write will eventually drift from what it summarises. Only the
-- functions below may change a deal.
revoke update on public.deals from authenticated;

-- The host fronts the money and buys the goods, so they hold a slot from the
-- moment the deal exists. Set here rather than in Dart so that no code path can
-- create a deal whose numbers lie.
create or replace function public.set_available_slots_for_new_deal()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.available_slots := new.total_slots - 1;
  return new;
end;
$$;

drop trigger if exists deals_set_available_slots on public.deals;
create trigger deals_set_available_slots
before insert on public.deals
for each row
execute function public.set_available_slots_for_new_deal();

create or replace function public.reserve_host_slot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.deal_reservations (deal_id, user_id)
  values (new.id, new.created_by);
  return new;
end;
$$;

drop trigger if exists deals_reserve_host_slot on public.deals;
create trigger deals_reserve_host_slot
after insert on public.deals
for each row
execute function public.reserve_host_slot();

-- Claiming a slot. The whole point of this function is that the check and the
-- write happen in ONE transaction: doing it from the client would let two
-- students both read "1 slot left" and both insert, overselling the deal.
create or replace function public.reserve_slot(p_deal_id uuid)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.deals d
    join public.hub_memberships m on m.hub_id = d.hub_id
    where d.id = p_deal_id and m.user_id = v_user_id
  ) then
    raise exception 'Deal not available.' using errcode = '42501';
  end if;

  -- The primary key rejects a second claim by the same student (23505).
  insert into public.deal_reservations (deal_id, user_id)
  values (p_deal_id, v_user_id);

  -- Concurrent callers serialise on this row. Under READ COMMITTED the loser
  -- re-evaluates the WHERE after the winner commits, finds available_slots = 0,
  -- and updates nothing -- so v_deal stays null and the whole transaction
  -- (including the insert above) rolls back.
  update public.deals
  set available_slots = available_slots - 1
  where id = p_deal_id and available_slots > 0
  returning * into v_deal;

  if v_deal.id is null then
    raise exception 'Deal is full.' using errcode = 'P0001';
  end if;

  return v_deal;
end;
$$;

-- Releasing a slot.
create or replace function public.cancel_reservation(p_deal_id uuid)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_deleted int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  -- Everyone else is relying on the host. They cannot quietly slip out; to get
  -- out they must cancel the deal, which is the Automatic Deal Status card.
  if v_deal.created_by = v_user_id then
    raise exception 'Host cannot cancel.' using errcode = 'P0003';
  end if;

  -- The deadline is the commitment point: past it the host is about to spend
  -- real money, and the count they are spending against must be final.
  if v_deal.closes_at is not null and v_deal.closes_at <= now() then
    raise exception 'Deadline passed.' using errcode = 'P0004';
  end if;

  delete from public.deal_reservations
  where deal_id = p_deal_id and user_id = v_user_id;
  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  update public.deals
  set available_slots = available_slots + 1
  where id = p_deal_id and available_slots < total_slots
  returning * into v_deal;

  return v_deal;
end;
$$;

grant execute on function public.reserve_slot(uuid) to authenticated;
grant execute on function public.cancel_reservation(uuid) to authenticated;

-- Who is in a deal. Joins profiles for the display name, which cannot be read
-- from the table directly (its RLS is own-row-only, by design -- profiles also
-- holds emails). Same device deal_feed already uses for host_name.
create or replace view public.deal_participants as
select
  r.deal_id,
  r.user_id,
  r.reserved_at,
  p.display_name as student_name,
  (r.user_id = d.created_by) as is_host
from public.deal_reservations r
join public.deals d on d.id = r.deal_id
left join public.profiles p on p.user_id = r.user_id
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id and m.user_id = (select auth.uid())
);

grant select on public.deal_participants to authenticated;

-- Deals that already exist were published before the host held a slot. Give
-- each host their reservation and recompute the counter, so old and new deals
-- obey the same rule.
insert into public.deal_reservations (deal_id, user_id)
select id, created_by
from public.deals
where created_by is not null
on conflict do nothing;

update public.deals d
set available_slots = greatest(
  0,
  d.total_slots - (
    select count(*)
    from public.deal_reservations r
    where r.deal_id = d.id
  )
);
