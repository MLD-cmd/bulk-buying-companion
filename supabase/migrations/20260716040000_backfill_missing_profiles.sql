insert into public.profiles (user_id, email, display_name)
select
  u.id,
  coalesce(u.email, ''),
  nullif(u.raw_user_meta_data ->> 'display_name', '')
from auth.users u
where not exists (
  select 1
  from public.profiles p
  where p.user_id = u.id
);

update public.profiles p
set
  email = coalesce(nullif(p.email, ''), u.email, ''),
  display_name = coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(u.raw_user_meta_data ->> 'display_name', '')
  ),
  updated_at = now()
from auth.users u
where p.user_id = u.id
  and (
    p.email is null
    or p.email = ''
    or p.display_name is null
    or btrim(p.display_name) = ''
  );
