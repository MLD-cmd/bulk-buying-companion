alter table public.deals
  add column if not exists payment_method text,
  add column if not exists payment_account_name text,
  add column if not exists payment_account_handle text,
  add column if not exists payment_instructions text;

comment on column public.deals.payment_method is
  'Manual payment channel named by the host, such as GCash, Maya, cash, or bank transfer.';
comment on column public.deals.payment_account_name is
  'Optional recipient name students should pay for this deal.';
comment on column public.deals.payment_account_handle is
  'Optional account number, phone number, username, or handle for manual payment.';
comment on column public.deals.payment_instructions is
  'Optional short manual payment instructions from the host.';

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
  p.display_name as host_name,
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
