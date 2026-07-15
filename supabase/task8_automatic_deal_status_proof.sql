drop table if exists t_result;
create temporary table t_result (
  check_name text,
  passed boolean,
  detail text
);

do $test$
declare
  v_deal_id uuid;
  v_host uuid;
  v_other uuid;
  v_other_was_paid boolean;
begin
  select d.id, d.created_by, r.user_id, (r.paid_at is not null)
    into v_deal_id, v_host, v_other, v_other_was_paid
  from public.deals d
  join public.deal_reservations r
    on r.deal_id = d.id
   and r.user_id <> d.created_by
  where d.created_by is not null
    and d.purchased_at is null
    and d.cancelled_at is null
    and (d.closes_at is null or d.closes_at > now())
  order by d.created_at desc
  limit 1;

  if v_deal_id is null or v_host is null or v_other is null then
    insert into t_result values (
      'setup',
      false,
      'No active unpurchased deal with a non-host participant was found.'
    );
    return;
  end if;

  insert into t_result values (
    'setup',
    true,
    'deal=' || v_deal_id || ', host=' || v_host || ', other=' || v_other
  );

  perform set_config('request.jwt.claim.sub', v_other::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_other)::text,
    true
  );

  begin
    perform public.mark_purchased(v_deal_id);
    insert into t_result values ('non-host cannot buy', false, 'it allowed it');
  exception when sqlstate 'P0012' then
    insert into t_result values ('non-host cannot buy', true, 'P0012');
  end;

  begin
    perform public.cancel_deal(v_deal_id);
    insert into t_result values ('non-host cannot cancel', false, 'it allowed it');
  exception when sqlstate 'P0012' then
    insert into t_result values ('non-host cannot cancel', true, 'P0012');
  end;

  begin
    perform public.set_participant_paid(v_deal_id, v_other, true);
    insert into t_result values (
      'non-host cannot mark paid',
      false,
      'it allowed it'
    );
  exception when sqlstate 'P0012' then
    insert into t_result values ('non-host cannot mark paid', true, 'P0012');
  end;

  begin
    perform public.set_participant_collected(v_deal_id, v_other, true);
    insert into t_result values (
      'non-host cannot mark collected',
      false,
      'it allowed it'
    );
  exception when sqlstate 'P0012' then
    insert into t_result values ('non-host cannot mark collected', true, 'P0012');
  end;

  perform set_config('request.jwt.claim.sub', v_host::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_host)::text,
    true
  );

  begin
    perform public.set_participant_paid(v_deal_id, v_host, false);
    insert into t_result values (
      'host slot cannot be unpaid',
      false,
      'it allowed it'
    );
  exception when sqlstate 'P0013' then
    insert into t_result values ('host slot cannot be unpaid', true, 'P0013');
  end;

  begin
    perform public.set_participant_collected(v_deal_id, v_other, true);
    insert into t_result values (
      'no collecting before buying',
      false,
      'it allowed it'
    );
  exception when sqlstate 'P0007' then
    insert into t_result values ('no collecting before buying', true, 'P0007');
  end;

  perform public.set_participant_paid(v_deal_id, v_other, true);

  perform set_config('request.jwt.claim.sub', v_other::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_other)::text,
    true
  );

  begin
    perform public.cancel_reservation(v_deal_id);
    insert into t_result values (
      'a paid student cannot walk',
      false,
      'it allowed it'
    );
  exception when sqlstate 'P0011' then
    insert into t_result values ('a paid student cannot walk', true, 'P0011');
  end;

  perform set_config('request.jwt.claim.sub', v_host::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_host)::text,
    true
  );
  perform public.set_participant_paid(v_deal_id, v_other, v_other_was_paid);

  insert into t_result values ('cleanup', true, 'restored non-host paid state');
end;
$test$;

select * from t_result order by check_name;
