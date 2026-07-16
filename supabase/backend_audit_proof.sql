drop table if exists t_backend_audit_result;
create temporary table t_backend_audit_result (
  check_name text,
  passed boolean,
  detail text
);

insert into t_backend_audit_result
select
  'deals table exists',
  to_regclass('public.deals') is not null,
  coalesce(to_regclass('public.deals')::text, 'missing');

insert into t_backend_audit_result
select
  'deal_feed view exists',
  to_regclass('public.deal_feed') is not null,
  coalesce(to_regclass('public.deal_feed')::text, 'missing');

insert into t_backend_audit_result
select
  'deals price rejects sub-centavo',
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'deals'
      and c.conname = 'deals_total_price_check'
      and pg_get_constraintdef(c.oid) ilike '%total_price >= 0.01%'
  ),
  coalesce((
    select pg_get_constraintdef(c.oid)
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'deals'
      and c.conname = 'deals_total_price_check'
  ), 'missing');

insert into t_backend_audit_result
select
  'deals rls enabled',
  relrowsecurity,
  relrowsecurity::text
from pg_class
where oid = 'public.deals'::regclass;

insert into t_backend_audit_result
select
  'deal reservations rls enabled',
  relrowsecurity,
  relrowsecurity::text
from pg_class
where oid = 'public.deal_reservations'::regclass;

insert into t_backend_audit_result
select
  'deals select policy scoped to own hub',
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'deals'
      and policyname = 'deals select in own hub'
      and cmd = 'SELECT'
      and qual ilike '%hub_memberships%'
      and qual ilike '%auth.uid%'
  ),
  coalesce((
    select qual
    from pg_policies
    where schemaname = 'public'
      and tablename = 'deals'
      and policyname = 'deals select in own hub'
  ), 'missing');

insert into t_backend_audit_result
select
  'deals insert policy requires own hub and author',
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'deals'
      and policyname = 'deals insert in own hub'
      and cmd = 'INSERT'
      and with_check ilike '%created_by%'
      and with_check ilike '%hub_memberships%'
      and with_check ilike '%auth.uid%'
  ),
  coalesce((
    select with_check
    from pg_policies
    where schemaname = 'public'
      and tablename = 'deals'
      and policyname = 'deals insert in own hub'
  ), 'missing');

insert into t_backend_audit_result
select
  'deals delete is not granted',
  not has_table_privilege('authenticated', 'public.deals', 'DELETE'),
  has_table_privilege('authenticated', 'public.deals', 'DELETE')::text;

insert into t_backend_audit_result
select
  'deals has no authenticated delete policy',
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'deals'
      and cmd = 'DELETE'
      and 'authenticated' = any(roles)
  ),
  coalesce((
    select string_agg(policyname, ', ' order by policyname)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'deals'
      and cmd = 'DELETE'
      and 'authenticated' = any(roles)
  ), 'none');

insert into t_backend_audit_result
select
  'deal_feed scopes inside the view',
  pg_get_viewdef('public.deal_feed'::regclass, true) ilike '%hub_memberships%'
    and pg_get_viewdef('public.deal_feed'::regclass, true) ilike '%auth.uid%',
  pg_get_viewdef('public.deal_feed'::regclass, true);

insert into t_backend_audit_result
select
  'deal_participants scopes inside the view',
  pg_get_viewdef('public.deal_participants'::regclass, true)
      ilike '%hub_memberships%'
    and pg_get_viewdef('public.deal_participants'::regclass, true)
      ilike '%auth.uid%',
  pg_get_viewdef('public.deal_participants'::regclass, true);

insert into t_backend_audit_result
select
  'security definer functions have scoped bodies',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname in (
        'deal_feed_row',
        'reserve_slot',
        'cancel_reservation',
        'set_participant_paid',
        'set_participant_collected',
        'mark_purchased',
        'cancel_deal'
      )
      and not (
        pg_get_functiondef(p.oid) ilike '%auth.uid%'
        or (
          p.proname = 'deal_feed_row'
          and pg_get_functiondef(p.oid) ilike '%public.deal_feed%'
        )
      )
  ),
  coalesce((
    select string_agg(p.proname, ', ' order by p.proname)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname in (
        'deal_feed_row',
        'reserve_slot',
        'cancel_reservation',
        'set_participant_paid',
        'set_participant_collected',
        'mark_purchased',
        'cancel_deal'
      )
      and not (
        pg_get_functiondef(p.oid) ilike '%auth.uid%'
        or (
          p.proname = 'deal_feed_row'
          and pg_get_functiondef(p.oid) ilike '%public.deal_feed%'
        )
      )
  ), 'all checked functions include caller scoping');

select *
from t_backend_audit_result
order by check_name;
