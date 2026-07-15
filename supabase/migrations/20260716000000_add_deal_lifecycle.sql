-- A deal's status was a column nothing ever updated. reserve_slot moved
-- available_slots and never touched status, so a full deal still showed an
-- "Open" badge, and every row in this database says 'open'.
--
-- The fix is to stop storing it. This migration stores the facts a status is a
-- reading of -- who paid, who collected, whether the host bought it or called it
-- off -- and Dart derives the status from them (see Deal.status). There is no
-- second copy to keep in step.

-- 1. The facts.

alter table public.deals
  add column if not exists purchased_at timestamptz,
  add column if not exists cancelled_at timestamptz;

alter table public.deal_reservations
  add column if not exists paid_at timestamptz,
  add column if not exists collected_at timestamptz;

-- 2. The host's slot is paid from the moment the deal exists.
--
-- They front the money and collect it; they cannot pay themselves. Were this
-- left null, "everyone has paid" could never become true and a deal could never
-- reach Ready to Purchase.

create or replace function public.reserve_host_slot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  insert into public.deal_reservations (deal_id, user_id, paid_at)
  values (new.id, new.created_by, now());
  return new;
end;
$fn$;

update public.deal_reservations r
set paid_at = coalesce(r.paid_at, r.reserved_at)
from public.deals d
where d.id = r.deal_id and d.created_by = r.user_id;

-- 3. The views expose the facts, and the status column goes.
--
-- The two existing RPCs return public.deals, whose rows carry no paid or
-- collected counts -- a Dart Deal built from one would report paidCount: 0 and
-- the badge would fall back to "Full" the moment the host marked someone paid.
-- Every RPC below returns the deal_feed row instead, as jsonb.
--
-- jsonb rather than `returns public.deal_feed`: a function whose return type is
-- a view's rowtype pins that view in place, and deal_feed has already had to be
-- dropped and recreated twice (removing a column requires it).
--
-- Changing a function's return type needs DROP, not CREATE OR REPLACE. Dropping
-- them here also frees the view to be replaced.

drop function if exists public.reserve_slot(uuid);
drop function if exists public.cancel_reservation(uuid);

drop view if exists public.deal_feed;

create view public.deal_feed as
select
  d.id,
  d.hub_id,
  d.created_by,
  d.title,
  d.description,
  d.category,
  d.total_price,
  d.amount,
  d.unit,
  d.total_slots,
  d.available_slots,
  d.pickup_location,
  d.closes_at,
  d.created_at,
  d.purchased_at,
  d.cancelled_at,
  p.display_name as host_name,
  c.paid_count,
  c.collected_count
from public.deals d
left join public.profiles p on p.user_id = d.created_by
left join lateral (
  select
    count(r.paid_at)      as paid_count,
    count(r.collected_at) as collected_count
  from public.deal_reservations r
  where r.deal_id = d.id
) c on true
-- A view runs with its owner's rights and ignores RLS on the tables underneath,
-- so the view itself is the security boundary. Without this, any signed-in
-- student could read every hub's deals. Added 2026-07-14; keep it.
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id
    and m.user_id = (select auth.uid())
);

grant select on public.deal_feed to authenticated;

-- Nothing reads it, and every row holds the default. No information is lost.
-- Dropping the column drops deals_status_check with it.
alter table public.deals drop column status;

-- Who is in a deal, and where each of them stands.
create or replace view public.deal_participants as
select
  r.deal_id,
  r.user_id,
  r.reserved_at,
  r.paid_at,
  r.collected_at,
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

-- 4. One shape for every RPC to hand back.
--
-- auth.uid() still resolves to the caller inside a security definer function, so
-- deal_feed's hub-membership filter applies to the caller, not the owner.

create or replace function public.deal_feed_row(p_deal_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $fn$
  select to_jsonb(f) from public.deal_feed f where f.id = p_deal_id;
$fn$;

-- 5. Claiming and releasing a slot, rebuilt to return the feed row and to
--    respect the two new ends of a deal's life.

create or replace function public.reserve_slot(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_updated int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from public.hub_memberships m
    where m.hub_id = v_deal.hub_id and m.user_id = v_user_id
  ) then
    raise exception 'Deal not available.' using errcode = '42501';
  end if;

  -- Once the host has bought the goods or called the deal off, the count they
  -- spent money against is final. Nobody else joins.
  if v_deal.cancelled_at is not null or v_deal.purchased_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- The primary key rejects a second claim by the same student (23505).
  insert into public.deal_reservations (deal_id, user_id)
  values (p_deal_id, v_user_id);

  -- Concurrent callers serialise on this row. Under READ COMMITTED the loser
  -- re-evaluates the WHERE after the winner commits, finds available_slots = 0,
  -- updates nothing, and the whole transaction (including the insert above)
  -- rolls back.
  --
  -- Checked with row_count, not `returning * into v_deal`: v_deal is already
  -- populated from the select above, and plpgsql leaves it untouched when a
  -- RETURNING matches no rows -- so the null check would never fire.
  update public.deals
  set available_slots = available_slots - 1
  where id = p_deal_id and available_slots > 0;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'Deal is full.' using errcode = 'P0001';
  end if;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.cancel_reservation(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_reservation public.deal_reservations;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  -- Everyone else is relying on the host. They cannot quietly slip out; to get
  -- out they cancel the whole deal.
  if v_deal.created_by = v_user_id then
    raise exception 'Host cannot cancel.' using errcode = 'P0003';
  end if;

  if v_deal.cancelled_at is not null or v_deal.purchased_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- The deadline is the commitment point: past it the host is about to spend
  -- real money, and the count they are spending against must be final.
  if v_deal.closes_at is not null and v_deal.closes_at <= now() then
    raise exception 'Deadline passed.' using errcode = 'P0004';
  end if;

  select * into v_reservation
  from public.deal_reservations
  where deal_id = p_deal_id and user_id = v_user_id;

  if v_reservation.deal_id is null then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  -- Walking away after paying would leave the host holding money they owe back,
  -- with no record that they owe it. Talk to the host; they unmark the payment.
  if v_reservation.paid_at is not null then
    raise exception 'Already paid.' using errcode = 'P0011';
  end if;

  delete from public.deal_reservations
  where deal_id = p_deal_id and user_id = v_user_id;

  update public.deals
  set available_slots = available_slots + 1
  where id = p_deal_id and available_slots < total_slots;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

-- 6. The host's four levers.
--
-- Every one of them checks created_by = auth.uid() here, in Postgres, and not in
-- Dart. A client-side permission check is a suggestion, not a control: a student
-- who could mark themselves paid could push a deal to Ready to Purchase and send
-- the host out to spend money on a promise.
--
-- P0012 rather than the canonical 42501, because ReservationRepository already
-- maps 42501 to "You can only reserve slots in your own hub", and one code
-- cannot carry two meanings in one message table.

create or replace function public.set_participant_paid(
  p_deal_id uuid,
  p_user_id uuid,
  p_paid boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_updated int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- Unmarking is allowed: a host who mis-taps must be able to take it back, and
  -- a student cannot leave a deal they are marked paid for until they do.
  update public.deal_reservations
  set paid_at = case when p_paid then now() else null end
  where deal_id = p_deal_id and user_id = p_user_id;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.set_participant_collected(
  p_deal_id uuid,
  p_user_id uuid,
  p_collected boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_updated int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- Nobody collects goods that do not exist yet.
  if v_deal.purchased_at is null then
    raise exception 'Goods not bought yet.' using errcode = 'P0007';
  end if;

  update public.deal_reservations
  set collected_at = case when p_collected then now() else null end
  where deal_id = p_deal_id and user_id = p_user_id;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.mark_purchased(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  if v_deal.purchased_at is not null then
    raise exception 'Already bought.' using errcode = 'P0008';
  end if;

  -- Deliberately does NOT require the deal to be full or fully paid. A host who
  -- bought early has bought early; the app's job is to record that, not argue.
  update public.deals
  set purchased_at = now()
  where id = p_deal_id;

  -- The host is standing there holding the goods, so their own share is
  -- collected. Otherwise they would have to tick themselves off a list to
  -- confirm they had handed themselves their own rice.
  update public.deal_reservations
  set collected_at = now()
  where deal_id = p_deal_id and user_id = v_deal.created_by;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.cancel_deal(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Already cancelled.' using errcode = 'P0009';
  end if;

  -- Completed, by the same rule Dart uses: bought, and nobody left to collect.
  -- The goods are gone; there is nothing left to call off.
  if v_deal.purchased_at is not null and not exists (
    select 1
    from public.deal_reservations r
    where r.deal_id = p_deal_id and r.collected_at is null
  ) then
    raise exception 'Deal is completed.' using errcode = 'P0010';
  end if;

  update public.deals
  set cancelled_at = now()
  where id = p_deal_id;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

grant execute on function public.reserve_slot(uuid) to authenticated;
grant execute on function public.cancel_reservation(uuid) to authenticated;
grant execute on function public.set_participant_paid(uuid, uuid, boolean) to authenticated;
grant execute on function public.set_participant_collected(uuid, uuid, boolean) to authenticated;
grant execute on function public.mark_purchased(uuid) to authenticated;
grant execute on function public.cancel_deal(uuid) to authenticated;
