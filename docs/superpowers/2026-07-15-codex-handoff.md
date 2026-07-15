# Codex Handoff — Automatic Deal Status

Date: 2026-07-15

This note records what Codex continued after Claude hit the session limit during
Automatic Deal Status work.

## Starting Point

Claude had stopped around:

- ADS Task 6: Details screen shows the lifecycle
- ADS Task 7: The board tells the truth
- ADS Task 8: Prove in SQL, verify on emulator

The last review notes called out:

- Confirm host-only paid/collected controls are actually gated in the widget tree.
- Restore the quieter styling on the `(organiser)` participant label.
- Add coverage that the host cannot unpay themselves.
- Add/confirm coverage for marking students collected.
- Continue into the board status work.

## What Codex Changed

### Task 6 Follow-Up

- Kept the host-only participant controls in `DealDetailsScreen`.
- Added a widget assertion that `(organiser)` keeps an explicit muted style.
- Added a repository invariant: the host slot is always paid and cannot be
  unmarked.
- Added Supabase error mapping for SQL error code `P0013`.
- Added the same host-paid guard to
  `supabase/migrations/20260716000000_add_deal_lifecycle.sql`.

Touched files:

- `lib/data/repositories/reservation_repository.dart`
- `supabase/migrations/20260716000000_add_deal_lifecycle.sql`
- `test/data/repositories/reservation_repository_test.dart`
- `test/ui/split_board/deal_details_screen_test.dart`

### Task 7 Follow-Up

- Added deal-card tests proving lifecycle badges render correctly:
  - `Full`
  - `Filling fast`
  - `Ready for pickup`
- Added a board-level navigation test proving the Split Board updates after the
  details screen returns a changed deal state.

Touched files:

- `test/ui/split_board/deal_card_test.dart`
- `test/ui/split_board/split_board_screen_test.dart`

## Verification Run

Codex ran:

```bash
flutter analyze
flutter test
```

Results:

- `flutter analyze`: no issues found.
- `flutter test`: all 240 tests passed.

## Current Status

Code-side work for ADS Task 6 and ADS Task 7 is covered and verified.

Remaining:

- ADS Task 8 emulator/manual app verification.

Task 8 is partially complete. The lifecycle migration was applied in Supabase
SQL editor and the live SQL proof passed. Emulator/manual app verification has
not been run yet.

## Task 8 SQL Proof

Status: passed in Supabase SQL editor. Emulator/manual verification is still
pending.

Run this after applying `supabase/migrations/20260716000000_add_deal_lifecycle.sql`.

The same proof query is also saved as:

- `supabase/task8_automatic_deal_status_proof.sql`

Expected result:

- Nine rows.
- Every row should have `passed = true`.
- If the first row is `setup` with `passed = false`, the live database needs an
  active deal with at least one non-host participant before this proof can run.

```sql
drop table if exists t_result;
create temporary table t_result (
  check_name text,
  passed boolean,
  detail text
) on commit drop;

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

  -- Supabase auth.uid() usually reads request.jwt.claim.sub. Set both forms so
  -- the proof works across local/live SQL editor differences.
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

  -- Now impersonate the host.
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

  -- A student who has paid cannot quietly leave.
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

  -- Restore the non-host participant's original paid state.
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
```

### SQL Editor Attempts And Results

First proof attempt failed because the live database did not yet have the
lifecycle columns:

```text
ERROR: 42703: column r.paid_at does not exist
```

Initial schema check:

| has_paid_at | has_collected_at | has_purchased_at | has_cancelled_at |
|---|---|---|---|
| false | false | false | false |

The first migration paste attempt failed because Supabase appears to have run a
selected fragment instead of the file from the top:

```text
ERROR: 42601: syntax error at or near ")"
LINE 1: );
        ^
```

Supabase CLI recheck:

```text
supabase migration list
Cannot find project ref. Have you run supabase link?
```

Conclusion: the CLI is installed locally, but this repo is not linked to the
live Supabase project. Browser SQL editor remained the apply path.

The second migration apply attempt exposed a real idempotency issue:

```text
ERROR: 42P16: cannot change name of view column "student_name" to "paid_at"
HINT: Use ALTER VIEW ... RENAME COLUMN ... to change name of view column instead.
```

Fix applied locally:

- Changed `alter table public.deals drop column status` to
  `drop column if exists status`, so the migration can be rerun after a partial
  SQL-editor apply.
- Added `drop view if exists public.deal_participants;` before recreating
  `deal_participants`.

The updated migration then ran successfully:

```text
Success. No rows returned.
```

Post-migration schema check:

| has_paid_at | has_collected_at | has_purchased_at | has_cancelled_at |
|---|---|---|---|
| true | true | true | true |

One proof attempt only ran the setup statements:

```text
drop table if exists t_result;
create temporary table t_result (...);

Result: Success. No rows returned.
```

To reduce copy/paste misses, the standalone proof file was added at
`supabase/task8_automatic_deal_status_proof.sql`.

Final Task 8 SQL proof result:

| check_name | passed | detail |
|---|---|---|
| a paid student cannot walk | true | P0011 |
| cleanup | true | restored non-host paid state |
| host slot cannot be unpaid | true | P0013 |
| no collecting before buying | true | P0007 |
| non-host cannot buy | true | P0012 |
| non-host cannot cancel | true | P0012 |
| non-host cannot mark collected | true | P0012 |
| non-host cannot mark paid | true | P0012 |
| setup | true | deal `46d2bb10-3578-4d3f-8b22-59c54cca1947` found with host and non-host participant |

Conclusion: the live SQL proof passed. The remaining Task 8 work is emulator or
manual app verification.

## Notes

- `AGENTS.md` is untracked and was not touched.
- Codex did not commit these changes.
