-- Backend audit follow-up.
--
-- `public.deals` originally lived only in the Supabase dashboard, so older
-- environments can have broader grants or looser checks than a fresh rebuild
-- from migrations. Keep this as a real migration, not only a rewrite of the
-- first migration, so already-created projects are tightened too.

alter table public.deals
  drop constraint if exists deals_total_price_check;

alter table public.deals
  add constraint deals_total_price_check check (total_price >= 0.01);

alter table public.deals enable row level security;

grant select, insert on public.deals to authenticated;
revoke update on public.deals from authenticated;
revoke delete on public.deals from authenticated;

drop policy if exists "deals select in own hub" on public.deals;
create policy "deals select in own hub"
on public.deals
for select
to authenticated
using (
  exists (
    select 1
    from public.hub_memberships m
    where m.hub_id = deals.hub_id
      and m.user_id = (select auth.uid())
  )
);

drop policy if exists "deals insert in own hub" on public.deals;
create policy "deals insert in own hub"
on public.deals
for insert
to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1
    from public.hub_memberships m
    where m.hub_id = deals.hub_id
      and m.user_id = (select auth.uid())
  )
);

-- The app cancels deals by preserving the row and setting cancelled_at through
-- `public.cancel_deal`. Direct deletes would erase the payment/reservation
-- trail, so no delete policy is created and delete privilege is revoked above.
drop policy if exists "deals delete own row" on public.deals;
drop policy if exists "deals delete own hub" on public.deals;
