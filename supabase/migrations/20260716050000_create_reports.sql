create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  deal_id uuid not null references public.deals (id) on delete cascade,
  reported_user_id uuid references auth.users (id) on delete set null,
  target_type text not null check (target_type in ('deal', 'user')),
  reason text not null check (
    reason in ('suspicious', 'inappropriate', 'problematic_user', 'other')
  ),
  explanation text,
  status text not null default 'open' check (
    status in ('open', 'reviewed', 'dismissed', 'action_taken')
  ),
  created_at timestamptz not null default now(),
  constraint reports_user_target_requires_user check (
    target_type <> 'user' or reported_user_id is not null
  )
);

create index if not exists reports_reporter_id_idx
  on public.reports (reporter_id);

create index if not exists reports_deal_id_idx
  on public.reports (deal_id);

create index if not exists reports_reported_user_id_idx
  on public.reports (reported_user_id);

alter table public.reports enable row level security;

grant select, insert on public.reports to authenticated;
revoke update, delete on public.reports from authenticated;

drop policy if exists "reports select own rows" on public.reports;
create policy "reports select own rows"
on public.reports
for select
to authenticated
using (reporter_id = (select auth.uid()));

drop policy if exists "reports insert own row" on public.reports;
create policy "reports insert own row"
on public.reports
for insert
to authenticated
with check (
  reporter_id = (select auth.uid())
  and exists (
    select 1
    from public.deals d
    join public.hub_memberships m on m.hub_id = d.hub_id
    where d.id = reports.deal_id
      and m.user_id = (select auth.uid())
  )
);
