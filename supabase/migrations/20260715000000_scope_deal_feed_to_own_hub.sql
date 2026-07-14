-- deal_feed had no where clause, so it returned every deal in every hub.
--
-- A view runs with its owner's rights, not the caller's, so it does not inherit
-- the row-level security of the tables underneath it. That bypass is the point
-- here -- display_name lives in profiles, whose policy is own-row-only -- but it
-- means the view has to do the scoping itself, and this one did not. Any
-- authenticated student could read the whole table through it: titles, prices,
-- pickup locations, host ids, and the display name of every host in the app.
--
-- The app only ever asks for its own hub (SplitBoardViewModel passes the joined
-- hub id, and the hub chip on the board is a label, not a picker), so the filter
-- below takes nothing away from a legitimate reader. It only stops a client that
-- skips the app and queries the view directly.
--
-- auth.uid() still resolves to the caller inside a view like this, which is what
-- makes the check work at all.
create or replace view public.deal_feed as
select
  d.id,
  d.hub_id,
  d.created_by,
  d.title,
  d.description,
  d.category,
  d.total_price,
  d.quantity,
  d.total_slots,
  d.available_slots,
  d.pickup_location,
  d.status,
  d.closes_at,
  d.created_at,
  p.display_name as host_name
from public.deals d
left join public.profiles p on p.user_id = d.created_by
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id
    and m.user_id = (select auth.uid())
);

grant select on public.deal_feed to authenticated;
