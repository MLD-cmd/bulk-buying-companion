-- Personalised deal recommendations.
--
-- Two facts drive the ranking, and both are per-student, so both live behind
-- own-row RLS: the categories a student says they care about, and the deals a
-- student has waved away. Everything else the ranker uses -- which deals a
-- student has joined, how urgent a deal is -- is already derivable from the
-- deals and reservations tables, so nothing new is stored for it.

-- The categories a student has opted into. An array rather than a join table:
-- there are four of them, they are read whole every time, and no query ever
-- asks "who prefers grocery". Constrained to the same four the deals table
-- allows, so a value that could never match a deal cannot be written.
alter table public.profiles
  add column if not exists preferred_categories text[] not null default '{}';

alter table public.profiles
  drop constraint if exists profiles_preferred_categories_valid;

alter table public.profiles
  add constraint profiles_preferred_categories_valid check (
    preferred_categories <@ array['grocery', 'household', 'drinks', 'pantry']::text[]
  );

-- A deal a student dismissed from their recommendations. One row per
-- (student, deal); dismissing the same deal twice is the same fact, so the
-- pair is the primary key. Cascades on both sides: a deleted deal or a deleted
-- account leaves no orphan dismissals behind.
create table if not exists public.dismissed_recommendations (
  user_id uuid not null references auth.users (id) on delete cascade,
  deal_id uuid not null references public.deals (id) on delete cascade,
  dismissed_at timestamptz not null default now(),
  primary key (user_id, deal_id)
);

-- No index on user_id alone: the primary key already leads with it, so a
-- second index would only duplicate that lookup. deal_id has no such cover --
-- it is the second column of the composite key -- so it gets its own index,
-- the same as any other foreign key column. Without it, a deal deletion's
-- cascade has to sequentially scan this table to find the rows to remove.
create index if not exists dismissed_recommendations_deal_id_idx
  on public.dismissed_recommendations (deal_id);

alter table public.dismissed_recommendations enable row level security;

grant select, insert, delete on public.dismissed_recommendations to authenticated;
revoke update on public.dismissed_recommendations from authenticated;

drop policy if exists "dismissed select own rows"
  on public.dismissed_recommendations;
create policy "dismissed select own rows"
on public.dismissed_recommendations
for select
to authenticated
using (user_id = (select auth.uid()));

-- Insert is own-row, and the deal has to be one the student could actually see
-- -- a deal in their own hub -- so a dismissal cannot name a deal outside it.
drop policy if exists "dismissed insert own row"
  on public.dismissed_recommendations;
create policy "dismissed insert own row"
on public.dismissed_recommendations
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.deals d
    join public.hub_memberships m on m.hub_id = d.hub_id
    where d.id = dismissed_recommendations.deal_id
      and m.user_id = (select auth.uid())
  )
);

-- Undismissing is deleting your own row, so a student can bring a deal back.
drop policy if exists "dismissed delete own row"
  on public.dismissed_recommendations;
create policy "dismissed delete own row"
on public.dismissed_recommendations
for delete
to authenticated
using (user_id = (select auth.uid()));
