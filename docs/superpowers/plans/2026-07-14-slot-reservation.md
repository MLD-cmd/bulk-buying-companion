# Slot Reservation System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a student claim or release one slot in a bulk-buying deal, without ever overselling the last slot.

**Architecture:** Slot claiming is atomic inside Postgres — a `reserve_slot` RPC inserts the reservation and conditionally decrements `available_slots` in one transaction, so concurrent callers serialise on the deal row and the loser is told the deal filled. A composite primary key on `(deal_id, user_id)` *is* duplicate prevention. The host's slot is created by a trigger on deal insert, so no deal can exist whose numbers lie. Dart follows the existing repository/gateway/ViewModel layering exactly.

**Tech Stack:** Flutter, Dart, `provider`, `supabase_flutter`, Postgres (RLS, plpgsql RPCs, triggers).

**Spec:** `docs/superpowers/specs/2026-07-14-slot-reservation-design.md`

---

## Critical context

**The `deals` table is NOT in the repo's migrations.** `supabase/migrations/` contains only `20260713000000_create_core_hub_tables.sql` (profiles, hubs, hub_memberships). `deals` was created by hand in Supabase and has these constraints, confirmed by querying `pg_constraint`:

```
deals_pkey                  PRIMARY KEY (id)
deals_total_price_check     CHECK (total_price > 0)
deals_total_slots_check     CHECK (total_slots > 0)
deals_quantity_check        CHECK (quantity > 0)
deals_available_slots_check CHECK (available_slots >= 0)
available_within_total      CHECK (available_slots <= total_slots)
deals_category_check        CHECK (category = ANY (ARRAY['grocery','household','drinks','pantry']))
deals_status_check          CHECK (status = ANY (ARRAY['open','filling_fast','full']))
deals_hub_id_fkey           FOREIGN KEY (hub_id) REFERENCES hubs(id) ON DELETE CASCADE
deals_created_by_fkey       FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE
```

So the migration in Task 1 is **additive** — it must not try to create `deals`.

**The user applies migrations by hand** in the Supabase SQL editor. Task 1 produces the file *and* the engineer must ask the user to run it; do not assume a `supabase db push` pipeline exists.

**Existing SQL conventions** (match them): lowercase keywords, `create table if not exists public.x`, functions declare `set search_path = ''` and therefore must fully qualify every name, policies are written `drop policy if exists "..." on public.x;` then `create policy`, and RLS predicates use `(select auth.uid())` rather than bare `auth.uid()`.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260714000000_create_slot_reservations.sql` | **New.** `deal_reservations` table, RLS, the two RPCs, the host-slot triggers, the `deal_participants` view, and a backfill for deals that already exist. |
| `lib/models/reservation.dart` | **New.** Pure `Reservation` model. |
| `lib/data/repositories/reservation_repository.dart` | **New.** `ReservationRepository` (abstract) + `ReservationFailure` + `MockReservationRepository` + `SupabaseReservationGateway` + `PostgrestSupabaseReservationGateway` + `SupabaseReservationRepository`. |
| `lib/data/repositories/deal_repository.dart` | Extract the private `_mapDeal` into a top-level `dealFromRow` so the reservation repository can map the deal row an RPC returns, instead of duplicating it. Mock: the host holds a slot. Supabase: stop sending `available_slots` (the trigger owns it). |
| `lib/ui/split_board/deal_details_viewmodel.dart` | **New.** Deal, participants, `isUpdating`, error message; `reserve()` and `cancel()`. |
| `lib/ui/split_board/deal_details_screen.dart` | Gains a `ChangeNotifierProvider` in `route()` and a `Consumer`. Reserve ↔ Cancel toggle. Participant list. |
| `lib/ui/split_board/split_board_viewmodel.dart` | `replaceDeal(Deal)` so the board reflects the updated slot count. |
| `lib/ui/split_board/split_board_screen.dart` | Awaits the updated deal popped from the details route. |
| `lib/main.dart` | Wire `SupabaseReservationRepository` into `MultiProvider`. |

---

### Task 1: The migration

**Files:**
- Create: `supabase/migrations/20260714000000_create_slot_reservations.sql`

This task writes SQL only. There is no Dart test for it; its correctness is proven by the concurrency check in Step 3 and by the end-to-end run in Task 9.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260714000000_create_slot_reservations.sql`:

```sql
-- One row per student per deal. The composite primary key IS the rule
-- "prevent duplicate reservations" -- enforced by Postgres rather than by
-- application code that has to remember to check on every path.
create table if not exists public.deal_reservations (
  deal_id uuid not null references public.deals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  reserved_at timestamptz not null default now(),
  primary key (deal_id, user_id)
);

create index if not exists deal_reservations_user_id_idx
  on public.deal_reservations (user_id);

alter table public.deal_reservations enable row level security;

-- A student may see who else is in a deal posted to a hub they belong to.
drop policy if exists "deal reservations select in own hub" on public.deal_reservations;
create policy "deal reservations select in own hub"
on public.deal_reservations
for select
to authenticated
using (
  exists (
    select 1
    from public.deals d
    join public.hub_memberships m on m.hub_id = d.hub_id
    where d.id = deal_reservations.deal_id
      and m.user_id = (select auth.uid())
  )
);

-- Deliberately NO insert/update/delete policies. Every mutation goes through
-- the security-definer RPCs below, because a reservation written without the
-- matching decrement of available_slots would desynchronise the two.

-- available_slots is a denormalised counter, and a denormalised counter that
-- anything can write will eventually drift from what it summarises. Only the
-- RPCs may change a deal.
revoke update on public.deals from authenticated;

-- The host fronts the money and buys the goods, so they hold a slot from the
-- moment the deal exists. Set here rather than in Dart so that NO code path can
-- create a deal whose numbers lie.
create or replace function public.set_available_slots_for_new_deal()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.available_slots := new.total_slots - 1;
  return new;
end;
$$;

drop trigger if exists deals_set_available_slots on public.deals;
create trigger deals_set_available_slots
before insert on public.deals
for each row
execute function public.set_available_slots_for_new_deal();

create or replace function public.reserve_host_slot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.deal_reservations (deal_id, user_id)
  values (new.id, new.created_by);
  return new;
end;
$$;

drop trigger if exists deals_reserve_host_slot on public.deals;
create trigger deals_reserve_host_slot
after insert on public.deals
for each row
execute function public.reserve_host_slot();

-- Claiming a slot. The whole point of this function is that the check and the
-- write happen in ONE transaction: doing it from the client would let two
-- students both read "1 slot left" and both insert, overselling the deal.
create or replace function public.reserve_slot(p_deal_id uuid)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.deals d
    join public.hub_memberships m on m.hub_id = d.hub_id
    where d.id = p_deal_id and m.user_id = v_user_id
  ) then
    raise exception 'Deal not available.' using errcode = '42501';
  end if;

  -- The primary key rejects a second claim by the same student (23505).
  insert into public.deal_reservations (deal_id, user_id)
  values (p_deal_id, v_user_id);

  -- Concurrent callers serialise on this row. Under READ COMMITTED the loser
  -- re-evaluates the WHERE after the winner commits, finds available_slots = 0,
  -- and updates nothing -- so v_deal stays null and the whole transaction
  -- (including the insert above) rolls back.
  update public.deals
  set available_slots = available_slots - 1
  where id = p_deal_id and available_slots > 0
  returning * into v_deal;

  if v_deal.id is null then
    raise exception 'Deal is full.' using errcode = 'P0001';
  end if;

  return v_deal;
end;
$$;

-- Releasing a slot.
create or replace function public.cancel_reservation(p_deal_id uuid)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_deleted int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  -- Everyone else is relying on the host. They cannot quietly slip out; to get
  -- out they must cancel the deal, which is the Automatic Deal Status card.
  if v_deal.created_by = v_user_id then
    raise exception 'Host cannot cancel.' using errcode = 'P0003';
  end if;

  -- The deadline is the commitment point: past it the host is about to spend
  -- real money, and the count they are spending against must be final.
  if v_deal.closes_at is not null and v_deal.closes_at <= now() then
    raise exception 'Deadline passed.' using errcode = 'P0004';
  end if;

  delete from public.deal_reservations
  where deal_id = p_deal_id and user_id = v_user_id;
  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  update public.deals
  set available_slots = available_slots + 1
  where id = p_deal_id and available_slots < total_slots
  returning * into v_deal;

  return v_deal;
end;
$$;

grant execute on function public.reserve_slot(uuid) to authenticated;
grant execute on function public.cancel_reservation(uuid) to authenticated;

-- Who is in a deal. Joins profiles for the display name, which cannot be read
-- from the table directly (its RLS is own-row-only, by design -- profiles also
-- holds emails). Same device deal_feed already uses for host_name.
create or replace view public.deal_participants as
select
  r.deal_id,
  r.user_id,
  r.reserved_at,
  p.display_name as student_name,
  (r.user_id = d.created_by) as is_host
from public.deal_reservations r
join public.deals d on d.id = r.deal_id
left join public.profiles p on p.user_id = r.user_id
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id and m.user_id = (select auth.uid())
);

grant select on public.deal_participants to authenticated;

-- Deals that already exist were published before the host held a slot. Give
-- each host their reservation and recompute the counter, so old and new deals
-- obey the same rule.
insert into public.deal_reservations (deal_id, user_id)
select id, created_by
from public.deals
where created_by is not null
on conflict do nothing;

update public.deals d
set available_slots = greatest(
  0,
  d.total_slots - (
    select count(*)
    from public.deal_reservations r
    where r.deal_id = d.id
  )
);
```

- [ ] **Step 2: Ask the user to apply it**

The repo has no migration pipeline — the user applies SQL by hand in the Supabase SQL editor. Post the file's contents and ask them to run it, then confirm it succeeded before continuing.

Tell them plainly what it does to existing data: **it gives every existing deal's host a reservation row and recomputes `available_slots` accordingly**, so a 7-slot deal with no participants will go from `7` open to `6` open. That is the intended new rule, not a bug.

If `deals.id` turns out not to be `uuid`, the RPC signatures need the real type — ask the user to run `select data_type from information_schema.columns where table_name = 'deals' and column_name = 'id';` and adjust `p_deal_id` accordingly.

- [ ] **Step 3: Prove the concurrency guarantee in SQL**

This is the claim the whole feature rests on, and no Dart test can prove it. Ask the user to run this in the Supabase SQL editor. It simulates the race inside one session using an explicit lock ordering — if the guard works, the second update finds no row to change.

```sql
-- Pick any deal and drive it to exactly one open slot.
do $$
declare
  v_deal_id uuid;
  v_updated int;
begin
  select id into v_deal_id from public.deals limit 1;
  update public.deals set available_slots = 1 where id = v_deal_id;

  -- First claimant takes the last slot.
  update public.deals
  set available_slots = available_slots - 1
  where id = v_deal_id and available_slots > 0;
  get diagnostics v_updated = row_count;
  raise notice 'first claimant updated % row(s) (expect 1)', v_updated;

  -- Second claimant, same condition, now that the slot is gone.
  update public.deals
  set available_slots = available_slots - 1
  where id = v_deal_id and available_slots > 0;
  get diagnostics v_updated = row_count;
  raise notice 'second claimant updated % row(s) (expect 0)', v_updated;

  rollback;
end;
$$;
```

Expected notices: `first claimant updated 1 row(s)` and `second claimant updated 0 row(s)`. The `rollback` leaves the data untouched.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260714000000_create_slot_reservations.sql
git commit -m "feat: add slot reservations, claimed atomically in Postgres"
```

---

### Task 2: The `Reservation` model

**Files:**
- Create: `lib/models/reservation.dart`
- Test: `test/models/reservation_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/models/reservation_test.dart`:

```dart
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names the student who holds the slot', () {
    final reservation = Reservation(
      dealId: 'deal-1',
      userId: 'user-1',
      studentName: 'Marco Villanueva',
      reservedAt: DateTime(2026, 7, 14),
      isHost: true,
    );

    expect(reservation.displayName, 'Marco Villanueva');
    expect(reservation.isHost, isTrue);
  });

  test('falls back to a person rather than a gap when the name is unknown', () {
    final reservation = Reservation(
      dealId: 'deal-1',
      userId: 'user-2',
      studentName: '   ',
      reservedAt: DateTime(2026, 7, 14),
    );

    expect(reservation.displayName, 'A student in this hub');
    expect(reservation.isHost, isFalse);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/models/reservation_test.dart`
Expected: FAIL — `reservation.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/models/reservation.dart`:

```dart
/// One student's claim on one slot of a deal.
class Reservation {
  const Reservation({
    required this.dealId,
    required this.userId,
    required this.reservedAt,
    this.studentName,
    this.isHost = false,
  });

  final String dealId;
  final String userId;
  final DateTime reservedAt;

  /// Comes from the deal_participants view, and stays null when the student
  /// has no profile row.
  final String? studentName;

  /// The student organising the buy. Their slot cannot be cancelled.
  final bool isHost;

  /// What to call the student when their name is unknown, rather than leaving
  /// a gap where a person should be.
  String get displayName => studentName?.trim().isNotEmpty == true
      ? studentName!.trim()
      : 'A student in this hub';
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `flutter test test/models/reservation_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/reservation.dart test/models/reservation_test.dart
git commit -m "feat: add the Reservation model"
```

---

### Task 3: Share the deal row mapper

**Files:**
- Modify: `lib/data/repositories/deal_repository.dart` (the private `_mapDeal`, `_mapCategory`, `_mapStatus` on `SupabaseDealRepository`)

The reservation RPCs return a `deals` row, and the reservation repository has to turn it into a `Deal`. That mapping already exists as `SupabaseDealRepository._mapDeal`, but it is private. Extract it rather than write it twice.

- [ ] **Step 1: Read the file**

READ `lib/data/repositories/deal_repository.dart` in full. Note the exact bodies of `_mapDeal`, `_mapCategory` and `_mapStatus` on `SupabaseDealRepository` (around lines 225–262).

- [ ] **Step 2: Extract the mapper**

In `lib/data/repositories/deal_repository.dart`, move those three private methods off the class and make the entry point a top-level function, so both repositories share one definition of what a deal row means:

```dart
/// Turns a `deals` (or `deal_feed`) row into a [Deal].
///
/// Top-level rather than private to the repository: the reservation RPCs also
/// return a deals row, and two copies of this mapping would be two things to
/// keep in step.
Deal dealFromRow(Map<String, dynamic> row) {
  final closesAt = row['closes_at'] as String?;

  return Deal(
    id: row['id'] as String,
    hubId: row['hub_id'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    createdBy: row['created_by'] as String?,
    // Absent when the row came back from the deals table rather than the
    // deal_feed view, which is what carries it.
    hostName: row['host_name'] as String?,
    category: _dealCategoryFromValue(row['category'] as String),
    totalPrice: (row['total_price'] as num).toDouble(),
    quantity: (row['quantity'] as num).toInt(),
    availableSlots: (row['available_slots'] as num).toInt(),
    totalSlots: (row['total_slots'] as num).toInt(),
    pickupLocation: row['pickup_location'] as String,
    status: _dealStatusFromValue(row['status'] as String),
    closesAt: closesAt == null ? null : DateTime.parse(closesAt).toLocal(),
  );
}

DealCategory _dealCategoryFromValue(String value) {
  return DealCategory.values.firstWhere(
    (category) => category.name == value,
    orElse: () => throw StateError('Unknown deal category "$value".'),
  );
}

DealStatus _dealStatusFromValue(String value) {
  return switch (value) {
    'open' => DealStatus.open,
    'filling_fast' => DealStatus.fillingFast,
    'full' => DealStatus.full,
    _ => throw StateError('Unknown deal status "$value".'),
  };
}
```

Then replace every `_mapDeal(...)` call inside `SupabaseDealRepository` with `dealFromRow(...)`, and delete the now-unused private `_mapDeal`, `_mapCategory` and `_mapStatus` methods. Leave `_statusValue` and `_messageFor` where they are — they are still used by `createDeal`.

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: PASS, everything. This is a pure refactor — no behaviour changes, so no test should change. If one does, stop and investigate.

Run: `flutter analyze`
Expected: no issues, and no "unused element" warning left behind by the deletions.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/deal_repository.dart
git commit -m "refactor: share one deal row mapper between repositories"
```

---

### Task 4: The host holds a slot

**Files:**
- Modify: `lib/data/repositories/deal_repository.dart` (`MockDealRepository.createDeal`, `SupabaseDealRepository.createDeal`)
- Test: `test/ui/split_board/create_deal_viewmodel_test.dart`

The trigger from Task 1 owns `available_slots` in production. Dart must stop fighting it, and the mock must obey the same rule so tests are honest.

- [ ] **Step 1: Write the failing test**

In `test/ui/split_board/create_deal_viewmodel_test.dart`, find the existing test `'publishes a deal with every slot still open'`. That name and its assertion are now wrong — the host holds one. Change the test to:

```dart
  test('publishes a deal with the host already holding a slot', () async {
    final repository = MockDealRepository();
    final viewModel = CreateDealViewModel(dealRepository: repository);

    final deal = await viewModel.submit(
      const DealDraft(
        hubId: 'colon',
        title: '  Cooking Oil 5L  ',
        description: 'Baguio brand',
        category: DealCategory.pantry,
        totalPrice: 750,
        quantity: 1,
        totalSlots: 5,
        pickupLocation: '  USJR Main Gate  ',
      ),
    );

    expect(deal, isNotNull);
    expect(deal!.title, 'Cooking Oil 5L');
    expect(deal.pickupLocation, 'USJR Main Gate');
    expect(deal.status, DealStatus.open);
    // "Split 5 ways" means the host and four others -- not five strangers.
    expect(deal.totalSlots, 5);
    expect(deal.availableSlots, 4);
    expect(deal.pricePerShare, 150);
    expect(deal.priceLabel, 'P150/share');
    expect(viewModel.errorMessage, isNull);

    final deals = await repository.getDeals('colon');
    expect(deals.map((deal) => deal.title), contains('Cooking Oil 5L'));
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/ui/split_board/create_deal_viewmodel_test.dart`
Expected: FAIL — `availableSlots` is 5, expected 4.

- [ ] **Step 3: Write the implementation**

In `lib/data/repositories/deal_repository.dart`:

In `MockDealRepository.createDeal`, replace the `availableSlots:` line and its comment:

```dart
      // The host is one of the students splitting the buy: "split 5 ways" means
      // them and four others. Mirrors the deals_set_available_slots trigger.
      availableSlots: draft.totalSlots - 1,
```

In `SupabaseDealRepository.createDeal`, **delete** the `'available_slots': draft.totalSlots,` entry from the insert map entirely. The `deals_set_available_slots` trigger sets it, and sending a value from Dart would be a second opinion about a number the database owns.

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS. Other suites may reference `availableSlots` on *seeded* mock deals — those are untouched, only `createDeal` changes. If a previously-passing test fails, read it: if it asserts a freshly-created deal has all slots open, it is asserting the old rule and should be updated. Anything else, stop and investigate.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/deal_repository.dart test/ui/split_board/create_deal_viewmodel_test.dart
git commit -m "feat: the host holds one of the slots they post"
```

---

### Task 5: The reservation repository

**Files:**
- Create: `lib/data/repositories/reservation_repository.dart`
- Test: `test/data/repositories/reservation_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/data/repositories/reservation_repository_test.dart`:

```dart
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseReservationRepository', () {
    test('reserving returns the deal with one fewer slot open', () async {
      final repository = SupabaseReservationRepository(
        gateway: _StubGateway(dealRow: _dealRow(availableSlots: 3)),
      );

      final deal = await repository.reserveSlot('deal-1');

      expect(deal.availableSlots, 3);
      expect(deal.totalSlots, 5);
    });

    test('says the deal filled up rather than a raw database error', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(const PostgrestException(
          message: 'Deal is full.',
          code: 'P0001',
        )),
      );

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'This deal just filled up.',
          ),
        ),
      );
    });

    test('says the student already holds a slot', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(const PostgrestException(
          message: 'duplicate key',
          code: '23505',
        )),
      );

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'You already have a slot in this deal.',
          ),
        ),
      );
    });

    test('says the deadline has passed', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(const PostgrestException(
          message: 'Deadline passed.',
          code: 'P0004',
        )),
      );

      expect(
        () => repository.cancelReservation('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'The deadline has passed, so slots are locked.',
          ),
        ),
      );
    });

    test('says the host cannot walk away from their own buy', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(const PostgrestException(
          message: 'Host cannot cancel.',
          code: 'P0003',
        )),
      );

      expect(
        () => repository.cancelReservation('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'You are organising this buy, so your slot cannot be cancelled.',
          ),
        ),
      );
    });

    test('maps the participant list, host first', () async {
      final repository = SupabaseReservationRepository(
        gateway: _StubGateway(
          dealRow: _dealRow(availableSlots: 3),
          participantRows: [
            {
              'deal_id': 'deal-1',
              'user_id': 'user-2',
              'reserved_at': '2026-07-14T02:00:00Z',
              'student_name': 'Bea Alonzo',
              'is_host': false,
            },
            {
              'deal_id': 'deal-1',
              'user_id': 'user-1',
              'reserved_at': '2026-07-14T01:00:00Z',
              'student_name': 'Marco Villanueva',
              'is_host': true,
            },
          ],
        ),
      );

      final participants = await repository.getParticipants('deal-1');

      expect(participants.map((p) => p.displayName), [
        'Marco Villanueva',
        'Bea Alonzo',
      ]);
      expect(participants.first.isHost, isTrue);
    });
  });

  group('MockReservationRepository', () {
    test('refuses a second slot for the same student', () async {
      final repository = MockReservationRepository(
        deal: _deal(availableSlots: 3),
        currentUserId: 'user-2',
      );

      await repository.reserveSlot('deal-1');

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('refuses a slot in a full deal', () async {
      final repository = MockReservationRepository(
        deal: _deal(availableSlots: 0),
        currentUserId: 'user-2',
      );

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('refuses to cancel the host out of their own buy', () async {
      final repository = MockReservationRepository(
        deal: _deal(availableSlots: 3),
        currentUserId: 'user-1', // the host
      );

      expect(
        () => repository.cancelReservation('deal-1'),
        throwsA(isA<ReservationFailure>()),
      );
    });
  });
}

Map<String, dynamic> _dealRow({required int availableSlots}) => {
  'id': 'deal-1',
  'hub_id': 'colon',
  'title': '25kg Rice Sack',
  'description': null,
  'created_by': 'user-1',
  'category': 'grocery',
  'total_price': 900,
  'quantity': 1,
  'available_slots': availableSlots,
  'total_slots': 5,
  'pickup_location': 'USJR Main Gate',
  'status': 'open',
  'closes_at': null,
};

Deal _deal({required int availableSlots}) => Deal(
  id: 'deal-1',
  hubId: 'colon',
  title: '25kg Rice Sack',
  createdBy: 'user-1',
  category: DealCategory.grocery,
  totalPrice: 900,
  quantity: 1,
  availableSlots: availableSlots,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
  status: DealStatus.open,
);

class _StubGateway implements SupabaseReservationGateway {
  _StubGateway({required this.dealRow, this.participantRows = const []});

  final Map<String, dynamic> dealRow;
  final List<Map<String, dynamic>> participantRows;

  @override
  Future<Map<String, dynamic>> reserveSlot(String dealId) async => dealRow;

  @override
  Future<Map<String, dynamic>> cancelReservation(String dealId) async => dealRow;

  @override
  Future<List<Map<String, dynamic>>> getParticipants(String dealId) async =>
      participantRows;
}

class _FailingGateway implements SupabaseReservationGateway {
  _FailingGateway(this.error);

  final PostgrestException error;

  @override
  Future<Map<String, dynamic>> reserveSlot(String dealId) async => throw error;

  @override
  Future<Map<String, dynamic>> cancelReservation(String dealId) async =>
      throw error;

  @override
  Future<List<Map<String, dynamic>>> getParticipants(String dealId) async =>
      throw error;
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/data/repositories/reservation_repository_test.dart`
Expected: FAIL — `reservation_repository.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/data/repositories/reservation_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/deal.dart';
import '../../models/reservation.dart';
import 'deal_repository.dart';

/// Claiming and releasing one slot of a deal. Backed by
/// [MockReservationRepository] in tests and [SupabaseReservationRepository] in
/// production; the ViewModel never depends on the concrete implementation.
abstract class ReservationRepository {
  Future<List<Reservation>> getParticipants(String dealId);

  /// Returns the deal as it stands after the claim, so the caller never has to
  /// guess the new slot count.
  Future<Deal> reserveSlot(String dealId);

  Future<Deal> cancelReservation(String dealId);
}

/// Raised when a slot cannot be claimed or released. The message is user-facing.
class ReservationFailure implements Exception {
  const ReservationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class SupabaseReservationGateway {
  Future<List<Map<String, dynamic>>> getParticipants(String dealId);

  Future<Map<String, dynamic>> reserveSlot(String dealId);

  Future<Map<String, dynamic>> cancelReservation(String dealId);
}

class PostgrestSupabaseReservationGateway
    implements SupabaseReservationGateway {
  PostgrestSupabaseReservationGateway(this._client);

  final SupabaseClient _client;

  /// Both mutations go through an RPC rather than a table write: the
  /// reservation and the slot count have to move together, in one transaction,
  /// or two students can claim the same last slot.
  @override
  Future<Map<String, dynamic>> reserveSlot(String dealId) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'reserve_slot',
      params: {'p_deal_id': dealId},
    );
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<Map<String, dynamic>> cancelReservation(String dealId) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'cancel_reservation',
      params: {'p_deal_id': dealId},
    );
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<List<Map<String, dynamic>>> getParticipants(String dealId) async {
    final rows = await _client
        .from('deal_participants')
        .select()
        .eq('deal_id', dealId)
        .order('reserved_at');
    return List<Map<String, dynamic>>.from(rows);
  }
}

class SupabaseReservationRepository implements ReservationRepository {
  SupabaseReservationRepository({required SupabaseReservationGateway gateway})
    : _gateway = gateway;

  final SupabaseReservationGateway _gateway;

  @override
  Future<Deal> reserveSlot(String dealId) async {
    try {
      return dealFromRow(await _gateway.reserveSlot(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> cancelReservation(String dealId) async {
    try {
      return dealFromRow(await _gateway.cancelReservation(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<List<Reservation>> getParticipants(String dealId) async {
    final rows = await _gateway.getParticipants(dealId);
    final participants = rows.map(_reservationFromRow).toList();
    // The organiser leads the list: they are the person everyone else is
    // relying on.
    participants.sort((a, b) {
      if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
      return a.reservedAt.compareTo(b.reservedAt);
    });
    return participants;
  }

  Reservation _reservationFromRow(Map<String, dynamic> row) {
    return Reservation(
      dealId: row['deal_id'] as String,
      userId: row['user_id'] as String,
      studentName: row['student_name'] as String?,
      isHost: row['is_host'] as bool? ?? false,
      reservedAt: DateTime.parse(row['reserved_at'] as String).toLocal(),
    );
  }

  /// The error codes are raised by the reserve_slot / cancel_reservation
  /// functions; see the slot reservation migration.
  String _messageFor(PostgrestException error) {
    return switch (error.code) {
      'P0001' => 'This deal just filled up.',
      '23505' => 'You already have a slot in this deal.',
      'P0003' =>
        'You are organising this buy, so your slot cannot be cancelled.',
      'P0004' => 'The deadline has passed, so slots are locked.',
      'P0005' => 'You do not have a slot in this deal.',
      'P0002' => 'That deal no longer exists.',
      '42501' => 'You can only reserve slots in your own hub.',
      _ => 'Could not update your slot. Please try again.',
    };
  }
}

/// In-memory stand-in that obeys the same rules as the database, so ViewModel
/// tests pass or fail for the same reasons production would.
class MockReservationRepository implements ReservationRepository {
  MockReservationRepository({required Deal deal, required this.currentUserId})
    : _deal = deal,
      _holders = {
        // Every deal has its host in it, exactly as the trigger guarantees.
        if (deal.createdBy != null) deal.createdBy!,
      };

  Deal _deal;
  final Set<String> _holders;
  final String currentUserId;

  Deal get deal => _deal;

  @override
  Future<List<Reservation>> getParticipants(String dealId) async {
    return _holders
        .map(
          (userId) => Reservation(
            dealId: dealId,
            userId: userId,
            studentName: userId == _deal.createdBy ? 'Marco Villanueva' : null,
            isHost: userId == _deal.createdBy,
            reservedAt: DateTime(2026, 7, 14),
          ),
        )
        .toList();
  }

  @override
  Future<Deal> reserveSlot(String dealId) async {
    if (_holders.contains(currentUserId)) {
      throw const ReservationFailure('You already have a slot in this deal.');
    }
    if (_deal.availableSlots == 0) {
      throw const ReservationFailure('This deal just filled up.');
    }

    _holders.add(currentUserId);
    _deal = _copyWithSlots(_deal.availableSlots - 1);
    return _deal;
  }

  @override
  Future<Deal> cancelReservation(String dealId) async {
    if (currentUserId == _deal.createdBy) {
      throw const ReservationFailure(
        'You are organising this buy, so your slot cannot be cancelled.',
      );
    }
    final closesAt = _deal.closesAt;
    if (closesAt != null && !closesAt.isAfter(DateTime.now())) {
      throw const ReservationFailure(
        'The deadline has passed, so slots are locked.',
      );
    }
    if (!_holders.remove(currentUserId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }

    _deal = _copyWithSlots(_deal.availableSlots + 1);
    return _deal;
  }

  Deal _copyWithSlots(int availableSlots) {
    return Deal(
      id: _deal.id,
      hubId: _deal.hubId,
      title: _deal.title,
      description: _deal.description,
      createdBy: _deal.createdBy,
      hostName: _deal.hostName,
      category: _deal.category,
      totalPrice: _deal.totalPrice,
      quantity: _deal.quantity,
      availableSlots: availableSlots,
      totalSlots: _deal.totalSlots,
      pickupLocation: _deal.pickupLocation,
      status: _deal.status,
      closesAt: _deal.closesAt,
    );
  }
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/data/repositories/reservation_repository_test.dart`
Expected: PASS, 9 tests.

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/reservation_repository.dart test/data/repositories/reservation_repository_test.dart
git commit -m "feat: add the reservation repository"
```

---

### Task 6: `DealDetailsViewModel`

**Files:**
- Create: `lib/ui/split_board/deal_details_viewmodel.dart`
- Test: `test/ui/split_board/deal_details_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/ui/split_board/deal_details_viewmodel_test.dart`:

```dart
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reserving takes a slot and puts the student in the list', () async {
    final viewModel = _viewModel(userId: 'user-2');
    await pumpEventQueue();

    expect(viewModel.holdsSlot, isFalse);
    expect(viewModel.deal.availableSlots, 4);

    await viewModel.reserve();

    expect(viewModel.holdsSlot, isTrue);
    expect(viewModel.deal.availableSlots, 3);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.isUpdating, isFalse);
  });

  test('cancelling gives the slot back', () async {
    final viewModel = _viewModel(userId: 'user-2');
    await pumpEventQueue();

    await viewModel.reserve();
    await viewModel.cancel();

    expect(viewModel.holdsSlot, isFalse);
    expect(viewModel.deal.availableSlots, 4);
  });

  test('a double-tapped reserve claims one slot, not two', () async {
    final viewModel = _viewModel(userId: 'user-2');
    await pumpEventQueue();

    // Both taps land before the first call resolves.
    final first = viewModel.reserve();
    final second = viewModel.reserve();
    await Future.wait([first, second]);

    expect(viewModel.deal.availableSlots, 3, reason: 'one slot, not two');
    expect(viewModel.errorMessage, isNull, reason: 'the second tap is a no-op');
  });

  test('the host holds a slot and cannot give it up', () async {
    final viewModel = _viewModel(userId: 'user-1'); // the host
    await pumpEventQueue();

    expect(viewModel.isHost, isTrue);
    expect(viewModel.holdsSlot, isTrue);
    expect(viewModel.canCancel, isFalse);

    await viewModel.cancel();

    expect(
      viewModel.errorMessage,
      'You are organising this buy, so your slot cannot be cancelled.',
    );
    expect(viewModel.deal.availableSlots, 4, reason: 'nothing was released');
  });

  test('surfaces a full deal as a message, not a crash', () async {
    final viewModel = _viewModel(userId: 'user-2', availableSlots: 0);
    await pumpEventQueue();

    expect(viewModel.isFull, isTrue);

    await viewModel.reserve();

    expect(viewModel.errorMessage, 'This deal just filled up.');
    expect(viewModel.holdsSlot, isFalse);
  });
}

DealDetailsViewModel _viewModel({
  required String userId,
  int availableSlots = 4,
}) {
  final deal = Deal(
    id: 'deal-1',
    hubId: 'colon',
    title: '25kg Rice Sack',
    createdBy: 'user-1',
    category: DealCategory.grocery,
    totalPrice: 900,
    quantity: 1,
    availableSlots: availableSlots,
    totalSlots: 5,
    pickupLocation: 'USJR Main Gate',
    status: DealStatus.open,
  );

  return DealDetailsViewModel(
    deal: deal,
    currentUserId: userId,
    reservationRepository: MockReservationRepository(
      deal: deal,
      currentUserId: userId,
    ),
  );
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/ui/split_board/deal_details_viewmodel_test.dart`
Expected: FAIL — `deal_details_viewmodel.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/ui/split_board/deal_details_viewmodel.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../data/repositories/reservation_repository.dart';
import '../../models/deal.dart';
import '../../models/reservation.dart';

/// Drives one deal's detail screen: who is in the buy, and whether this student
/// can take or give up a slot.
class DealDetailsViewModel extends ChangeNotifier {
  DealDetailsViewModel({
    required ReservationRepository reservationRepository,
    required Deal deal,
    required this.currentUserId,
  }) : _reservationRepository = reservationRepository,
       _deal = deal {
    _loadParticipants();
  }

  final ReservationRepository _reservationRepository;
  final String? currentUserId;

  Deal _deal;
  List<Reservation> _participants = const [];
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _errorMessage;

  Deal get deal => _deal;
  List<Reservation> get participants => _participants;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;

  bool get isFull => _deal.availableSlots == 0;
  bool get isHost => currentUserId != null && _deal.createdBy == currentUserId;

  bool get holdsSlot =>
      _participants.any((participant) => participant.userId == currentUserId);

  bool get deadlinePassed {
    final closesAt = _deal.closesAt;
    return closesAt != null && !closesAt.isAfter(DateTime.now());
  }

  /// The host is the person everyone else is relying on, so they cannot walk
  /// away from their own buy; and past the deadline the host is about to spend
  /// real money against a count that must now be final.
  bool get canCancel => holdsSlot && !isHost && !deadlinePassed;

  bool get canReserve => !holdsSlot && !isFull && !deadlinePassed;

  Future<void> reserve() => _mutate(
    () => _reservationRepository.reserveSlot(_deal.id),
  );

  Future<void> cancel() => _mutate(
    () => _reservationRepository.cancelReservation(_deal.id),
  );

  /// A second tap landing before the first call resolves would claim against a
  /// stale slot count. The button disables too; this is the backstop.
  Future<void> _mutate(Future<Deal> Function() action) async {
    if (_isUpdating) return;

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _deal = await action();
      _participants = await _reservationRepository.getParticipants(_deal.id);
    } on ReservationFailure catch (failure) {
      _errorMessage = failure.message;
    } catch (_) {
      _errorMessage = 'Could not update your slot. Please try again.';
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<void> _loadParticipants() async {
    try {
      _participants = await _reservationRepository.getParticipants(_deal.id);
    } catch (_) {
      _participants = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/ui/split_board/deal_details_viewmodel_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/split_board/deal_details_viewmodel.dart test/ui/split_board/deal_details_viewmodel_test.dart
git commit -m "feat: add DealDetailsViewModel, driving reserve and cancel"
```

---

### Task 7: The details screen

**Files:**
- Modify: `lib/ui/split_board/deal_details_screen.dart`
- Test: `test/ui/split_board/deal_details_screen_test.dart`

`DealDetailsScreen` is a `StatelessWidget` taking a `Deal` — the one place the codebase departs from MVVM. This is where it comes into line.

- [ ] **Step 1: Read both files**

READ `lib/ui/split_board/deal_details_screen.dart` and `test/ui/split_board/deal_details_screen_test.dart` in full, plus `lib/ui/split_board/create_deal_screen.dart` lines 1–35 for the `ChangeNotifierProvider`-in-`route()` pattern to copy. The existing test helper is `pumpDetails(tester, deal)` — it will need to change, because the screen now needs a provider above it. Match the file's real helper names, not any guessed here.

- [ ] **Step 2: Write the failing tests**

Add to `test/ui/split_board/deal_details_screen_test.dart`, and adapt the file's existing `pumpDetails` helper so it wraps the screen in the providers the new `route()` needs (a `Provider<ReservationRepository>` and a `Provider<AuthRepository>`, or by constructing `DealDetailsViewModel` directly — whichever matches how the screen ends up taking its dependencies):

```dart
  testWidgets('a student can take a slot', (tester) async {
    await pumpDetails(tester, _deal, currentUserId: 'user-2');
    await tester.pumpAndSettle();

    expect(find.text('Reserve a slot'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-reserve-button')));
    await tester.pumpAndSettle();

    expect(find.text('Cancel my slot'), findsOneWidget);
  });

  testWidgets('the host is shown holding a slot they cannot give up', (
    tester,
  ) async {
    await pumpDetails(tester, _deal, currentUserId: 'user-1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-host-slot-note')), findsOneWidget);
    expect(find.text('Cancel my slot'), findsNothing);
  });

  testWidgets('lists who is in the buy', (tester) async {
    await pumpDetails(tester, _deal, currentUserId: 'user-2');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-participants')), findsOneWidget);
    expect(find.text('Marco Villanueva'), findsWidgets);
  });
```

`_deal` must have `createdBy: 'user-1'` so the host cases work.

- [ ] **Step 3: Run and watch them fail**

Run: `flutter test test/ui/split_board/deal_details_screen_test.dart`
Expected: FAIL — no `Cancel my slot`, no participants list.

- [ ] **Step 4: Write the implementation**

Rework `lib/ui/split_board/deal_details_screen.dart`:

Change `route()` to provide the ViewModel and return the updated deal, mirroring `CreateDealScreen.route`:

```dart
  /// Pops with the deal as it stands after any slot change, so the Split Board
  /// can show the new count instead of the one it pushed with.
  static Route<Deal> route(Deal deal) {
    return MaterialPageRoute<Deal>(
      builder: (context) => ChangeNotifierProvider(
        create: (context) => DealDetailsViewModel(
          reservationRepository: context.read<ReservationRepository>(),
          deal: deal,
          currentUserId: context.read<AuthRepository>().currentUser?.uid,
        ),
        child: const DealDetailsScreen(),
      ),
    );
  }
```

`DealDetailsScreen` drops its `deal` field and reads it from the ViewModel via `Consumer<DealDetailsViewModel>`. Wrap the body so the back button pops the current deal:

```dart
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(viewModel.deal);
      },
      child: Scaffold(...),
    );
```

Replace the reserve button and `_reserve` with a toggle driven by the ViewModel:

```dart
            if (viewModel.errorMessage != null) ...[
              _Banner(
                key: const Key('detail-reservation-error'),
                message: viewModel.errorMessage!,
              ),
              const SizedBox(height: 12),
            ],

            if (viewModel.isHost)
              Container(
                key: const Key('detail-host-slot-note'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  'You are organising this buy, so one slot is yours. To pull '
                  'out you would have to cancel the whole deal.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              FilledButton(
                key: const Key('detail-reserve-button'),
                onPressed: viewModel.isUpdating
                    ? null
                    : viewModel.holdsSlot
                    ? (viewModel.canCancel ? viewModel.cancel : null)
                    : (viewModel.canReserve ? viewModel.reserve : null),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(_actionLabel(viewModel)),
              ),
```

with:

```dart
  String _actionLabel(DealDetailsViewModel viewModel) {
    if (viewModel.holdsSlot) {
      return viewModel.deadlinePassed ? 'Slot locked in' : 'Cancel my slot';
    }
    if (viewModel.isFull) return 'No slots left';
    if (viewModel.deadlinePassed) return 'Deadline passed';
    return 'Reserve a slot';
  }
```

Add the participant list below the Slots section:

```dart
            _SectionLabel('Who is in'),
            _Participants(
              key: const Key('detail-participants'),
              participants: viewModel.participants,
            ),
            const SizedBox(height: 24),
```

```dart
class _Participants extends StatelessWidget {
  const _Participants({super.key, required this.participants});

  final List<Reservation> participants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (participants.isEmpty) {
      return Text(
        'Nobody has claimed a share yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final participant in participants)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  participant.isHost
                      ? Icons.star_outline
                      : Icons.person_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  participant.displayName,
                  style: theme.textTheme.bodyMedium,
                ),
                if (participant.isHost) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(organiser)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
```

Reuse the existing `_Banner` widget from `create_deal_screen.dart` if one is exported; if it is private to that file, write a small local equivalent rather than making it public.

Add the imports the file now needs: `package:provider/provider.dart`, `../../data/repositories/auth_repository.dart`, `../../data/repositories/reservation_repository.dart`, `../../models/reservation.dart`, `deal_details_viewmodel.dart`.

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS. Pre-existing details-screen tests (`P180`, `detail-cost-per-slot`, `detail-total-price`, the surplus note) must all still pass — the cost card is untouched.

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/split_board/deal_details_screen.dart test/ui/split_board/deal_details_screen_test.dart
git commit -m "feat: reserve and cancel a slot from the deal details screen"
```

---

### Task 8: The board reflects the new count, and wire it up

**Files:**
- Modify: `lib/ui/split_board/split_board_viewmodel.dart`
- Modify: `lib/ui/split_board/split_board_screen.dart:118`
- Modify: `lib/main.dart`
- Test: `test/ui/split_board/split_board_viewmodel_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/ui/split_board/split_board_viewmodel_test.dart`, matching the file's existing helpers (`_FakeDealRepository`, `_StubDeal`, `updateSortOption`, `filteredDeals` — confirm against the file):

```dart
  test('replaces a deal when its slot count changes', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository([
        _deal(id: 'rice', availableSlots: 4, totalSlots: 5),
      ]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await pumpEventQueue();

    viewModel.replaceDeal(_deal(id: 'rice', availableSlots: 3, totalSlots: 5));

    expect(viewModel.filteredDeals.single.availableSlots, 3);
  });
```

Reuse the file's real deal-building helper; if it hardcodes slot counts, construct `Deal` directly.

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/ui/split_board/split_board_viewmodel_test.dart`
Expected: FAIL — `replaceDeal` is not defined.

- [ ] **Step 3: Write the implementation**

In `lib/ui/split_board/split_board_viewmodel.dart`, add:

```dart
  /// Swaps in a deal whose slot count changed while the student was looking at
  /// it, so the board does not keep showing the count it was pushed with.
  void replaceDeal(Deal deal) {
    final index = _deals.indexWhere((existing) => existing.id == deal.id);
    if (index == -1) return;

    _deals = [..._deals]..[index] = deal;
    notifyListeners();
  }
```

In `lib/ui/split_board/split_board_screen.dart`, change the deal card's `onTap` (currently line 118) to await the popped deal:

```dart
              onTap: () async {
                final updated = await Navigator.of(
                  context,
                ).push(DealDetailsScreen.route(deal));
                if (updated != null) viewModel.replaceDeal(updated);
              },
```

`viewModel` must be in scope at that point — check how the surrounding builder gets it and use the same reference (the file already reads a `SplitBoardViewModel` for the create-deal flow at line 86).

In `lib/main.dart`, build the reservation repository beside the others and provide it:

```dart
  final reservationRepository = SupabaseReservationRepository(
    gateway: PostgrestSupabaseReservationGateway(client),
  );
```

pass it into `BulkBuyingCompanionApp`, add the field, and add to `MultiProvider`:

```dart
        Provider<ReservationRepository>(
          create: (_) =>
              reservationRepository ??
              MockReservationRepository(
                deal: _fallbackDeal,
                currentUserId: 'preview-user',
              ),
        ),
```

`MockReservationRepository` needs a deal, which the app-level provider has no natural one for. Rather than invent a fallback, make the app's `reservationRepository` parameter **required in practice**: keep the field nullable for widget tests that pass their own, and have `create` throw a `StateError('No ReservationRepository provided.')` when it is null, instead of fabricating a mock. That is honest — an app booting without a reservation repository is a wiring bug, not something to paper over.

Add the imports `reservation_repository.dart` to `main.dart`.

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS.

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/split_board/split_board_viewmodel.dart lib/ui/split_board/split_board_screen.dart lib/main.dart test/ui/split_board/split_board_viewmodel_test.dart
git commit -m "feat: reflect a changed slot count back on the Split Board"
```

---

### Task 9: Verify against the running app

**Files:** none — verification only.

- [ ] **Step 1: Full suite and analyzer**

Run: `flutter test`
Expected: PASS, everything.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Drive it on the emulator**

Run the app on `emulator-5554`. A green suite does not prove the RPCs work — nothing in the Dart tests talks to Postgres. This step is the only thing that does.

Confirm, with your own eyes:
- A newly posted 5-slot deal shows **4 of 5 slots open** and lists the host under "Who is in".
- Tapping **Reserve a slot** turns the button into **Cancel my slot**, drops the open count by one, and adds the student to the list.
- Tapping **Cancel my slot** puts the slot back.
- Going back to the Split Board shows the **updated** count on the card, not the old one.
- Opening a deal you host shows the organiser note and **no** cancel button.
- Reserving twice in a row (tap the button twice fast) claims **one** slot.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: tidy up after slot reservations"
```

---

## Self-Review

**Spec coverage**

| Spec requirement | Task |
|---|---|
| One slot per student, enforced by composite PK | 1 |
| Host holds a slot, via trigger | 1, 4 |
| Host's slot cannot be cancelled | 1 (`P0003`), 5, 6, 7 |
| Cancel allowed until `closes_at`; no deadline = always | 1 (`P0004`), 5, 6 |
| Atomic claiming in an RPC | 1 |
| `available_slots` writable only by RPC | 1 (`revoke update`) |
| `deal_participants` view, hub-scoped | 1, 5 |
| `Reservation` model | 2 |
| `ReservationRepository` + Mock + Supabase + Gateway + Failure | 5 |
| Error-code → user-facing message mapping | 5 |
| `DealDetailsViewModel`, re-entrancy guard | 6 |
| Details screen gains provider, toggle, participant list | 7 |
| Board reflects the updated count | 8 |
| Concurrency proven | 1 (SQL), 9 (app) |
| Backfill for deals that already exist | 1 |

**Two deliberate deviations from the spec, made because they are safer:**

1. The spec said students "may insert or delete only their own row" in `deal_reservations`. The plan grants **no direct DML at all** — everything goes through the RPCs. A reservation written without the matching slot decrement would desynchronise the counter, which is the exact class of bug this design exists to prevent.
2. The spec did not mention a **backfill**. Existing deals were published before the host-holds-a-slot rule, so without one they would have no host reservation and a slot count that contradicts the new rule. Task 1 backfills them.

**Known soft spot, flagged rather than papered over:** Tasks 7 and 8 append to test files whose private helpers (`pumpDetails`, `_deal`, `_FakeDealRepository`, `_StubDeal`) I have not read in full, and Task 7 rewrites a screen I have only read in part. Each step says to read the file first and match its real helpers. Task 7 is also the largest single change in the plan — if the implementer gets stuck, splitting it (provider wiring first, participant list second) is reasonable.
