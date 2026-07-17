create or replace view public.deal_feed as
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
  coalesce(nullif(btrim(p.display_name), ''), split_part(p.email, '@', 1))
    as host_name,
  c.paid_count,
  c.collected_count,
  d.payment_method,
  d.payment_account_name,
  d.payment_account_handle,
  d.payment_instructions
from public.deals d
left join public.profiles p on p.user_id = d.created_by
left join lateral (
  select
    count(r.paid_at)      as paid_count,
    count(r.collected_at) as collected_count
  from public.deal_reservations r
  where r.deal_id = d.id
) c on true
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id
    and m.user_id = (select auth.uid())
);

grant select on public.deal_feed to authenticated;

create or replace view public.deal_participants as
select
  r.deal_id,
  r.user_id,
  r.reserved_at,
  r.paid_at,
  r.collected_at,
  coalesce(nullif(btrim(p.display_name), ''), split_part(p.email, '@', 1))
    as student_name,
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
