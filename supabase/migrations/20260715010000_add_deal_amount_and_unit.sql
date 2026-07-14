-- A deal's real measure lived only as text in its title: "25kg Rice Sack" was
-- stored as quantity 1, while a 24-pack of water was stored as quantity 24. So
-- the column meant two different things, and the app could tell a student what
-- they pay while having no idea what they receive.
--
-- amount + unit replaces it, and the unit carries the divisibility rule: 'pieces'
-- says the goods cannot be halved, 'kg' says they can.

alter table public.deals
  add column if not exists amount numeric,
  add column if not exists unit text;

-- The only row in this table is a test deal ("25kg Rice Sack") posted while
-- verifying slot reservation. Its measure exists only inside its title string, so
-- migrating it would mean parsing English out of free text to guess "25 kg" --
-- the same prose-matching that caused an auth bug on 2026-07-14. Delete the test
-- artifact rather than teach the schema a habit we just removed from the code.
-- The reservation row cascades.
delete from public.deals where amount is null;

alter table public.deals
  alter column amount set not null,
  alter column unit set not null;

alter table public.deals
  add constraint deals_amount_check check (amount > 0);

-- Stored by the Dart enum's name, as category already is: 'litre', not 'L'.
alter table public.deals
  add constraint deals_unit_check check (
    unit in ('kg', 'litre', 'pieces', 'packs', 'bottles', 'cans', 'sachets')
  );

-- The rule this whole change exists for. 30 eggs across 4 slots is 7.5 eggs, and
-- nobody can collect half an egg.
--
-- Enforced here, and not only in Dart, deliberately: a client-side check is a
-- convenience, not a control -- anything speaking to PostgREST can skip it. We
-- learned that the hard way from deal_feed the same week. If a deal that cannot
-- be physically fulfilled must not exist, the database is the thing that has to
-- refuse it.
alter table public.deals
  add constraint deals_goods_divide_check check (
    unit in ('kg', 'litre')
    or (amount = floor(amount) and (amount::int) % total_slots = 0)
  );

-- deal_feed selects quantity, so the view has to stop depending on the column
-- before it can be dropped.
--
-- It has to be DROP + CREATE, not CREATE OR REPLACE: replacing a view cannot
-- remove a column from its output ("cannot change name of view column").
--
-- Keeps the hub-membership scoping added on 2026-07-14. A view runs with its
-- owner's rights and ignores RLS on the tables underneath, so the view itself is
-- the security boundary -- without this where-clause any signed-in student could
-- read every hub's deals.
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

alter table public.deals drop column quantity;
