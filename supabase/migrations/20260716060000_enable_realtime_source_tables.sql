do $$
begin
  if to_regclass('public.deals') is not null then
    alter publication supabase_realtime add table public.deals;
  end if;
exception
  when duplicate_object then null;
  when undefined_object then null;
  when undefined_table then null;
end $$;

do $$
begin
  if to_regclass('public.deal_reservations') is not null then
    alter publication supabase_realtime add table public.deal_reservations;
  end if;
exception
  when duplicate_object then null;
  when undefined_object then null;
  when undefined_table then null;
end $$;

do $$
begin
  if to_regclass('public.hubs') is not null then
    alter publication supabase_realtime add table public.hubs;
  end if;
exception
  when duplicate_object then null;
  when undefined_object then null;
  when undefined_table then null;
end $$;

do $$
begin
  if to_regclass('public.hub_memberships') is not null then
    alter publication supabase_realtime add table public.hub_memberships;
  end if;
exception
  when duplicate_object then null;
  when undefined_object then null;
  when undefined_table then null;
end $$;

do $$
begin
  if to_regclass('public.reports') is not null then
    alter publication supabase_realtime add table public.reports;
  end if;
exception
  when duplicate_object then null;
  when undefined_object then null;
  when undefined_table then null;
end $$;
