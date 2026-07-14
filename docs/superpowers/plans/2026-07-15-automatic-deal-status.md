# Automatic Deal Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deal moves itself through Open → Full → Ready to Purchase → Ready for Pickup → Completed (plus Cancelled) as students reserve, pay, and collect — with the status derived from stored facts rather than kept in a column that nothing updates.

**Architecture:** Drop `deals.status`. Store five facts (`available_slots`, `paid_at` and `collected_at` per participant, `purchased_at` and `cancelled_at` per deal) and compute `DealStatus` in Dart on `Deal`, the way `CostSplit` and `PhysicalShare` already compute money and goods. Four new host-only security-definer RPCs write the facts; every RPC returns the `deal_feed` row as `jsonb` so the app always gets a renderable deal back.

**Tech Stack:** Flutter, Dart, `provider` (MVVM), Supabase (Postgres, RLS, views, security-definer RPCs).

**Spec:** `docs/superpowers/specs/2026-07-15-automatic-deal-status-design.md`

---

## Background the implementer needs

Read this before Task 1. It is not obvious from the code.

**The bug this card fixes.** `deals.status` is `not null default 'open'` and
**nothing has ever updated it**. `reserve_slot` moves `available_slots` but never
touches `status`, so a full deal still shows a green "Open" badge. Every row in
the live database holds `'open'`.

**You cannot write to `deals` from the app.** The slot-reservation migration ran
`revoke update on public.deals from authenticated`, and `deal_reservations` has
no insert/update/delete policy at all. Every mutation goes through a
`security definer` function. This is deliberate — a denormalised counter anything
can write will drift.

**`auth.uid()` still resolves to the caller inside a `security definer` function
and inside a view.** That is what makes the hub-membership scoping on `deal_feed`
work, and it is what makes the host checks below work.

**Enums persist by their Dart `name`.** `DealCategory.grocery` → `'grocery'`,
`DealUnit.litre` → `'litre'`. `DealStatus` is the exception: after this card it is
never persisted at all.

**Supabase's SQL editor mangles bare `$$`.** Use named dollar tags (`$fn$`) in
every function body, as the existing migrations do.

## File structure

| File | Responsibility |
|---|---|
| `lib/models/deal.dart` | `DealStatus` enum; `Deal` gains the four stored facts, derives `status`, `isFillingFast`, `statusLabel`, and the money the host is holding. **Modify.** |
| `lib/models/reservation.dart` | `Reservation` gains `paidAt` / `collectedAt`. **Modify.** |
| `supabase/migrations/20260716000000_add_deal_lifecycle.sql` | Columns, host-paid trigger, both views, drop `status`, six RPCs. **Create.** |
| `lib/data/repositories/deal_repository.dart` | `dealFromRow` maps the new columns; mock seeds and `createDeal` drop `status:`. **Modify.** |
| `lib/data/repositories/reservation_repository.dart` | Four new methods on the contract, the mock, and the Supabase implementation; new error messages. **Modify.** |
| `lib/ui/split_board/deal_details_viewmodel.dart` | Host actions and what the host is owed. **Modify.** |
| `lib/ui/split_board/deal_details_screen.dart` | Paid/collected per participant, host buttons, the cancel dialog. **Modify.** |
| `lib/ui/split_board/widgets/deal_card.dart` | Badge reads `statusLabel`; six statuses to colour. **Modify.** |
| `lib/ui/split_board/split_board_viewmodel.dart` | Hide finished deals by default. **Modify.** |
| `lib/ui/split_board/split_board_screen.dart` | Status filter lists six. **Modify.** |
| `test/models/deal_status_test.dart` | The derivation. **Create.** |

---

### Task 1: `DealStatus` and the derivation on `Deal`

`status` stops being a constructor argument and becomes a getter. That breaks
every `Deal(...)` call site, so this task fixes them all — it is one change:
"status is derived".

**Files:**
- Modify: `lib/models/deal.dart`
- Modify: `lib/data/repositories/deal_repository.dart` (mock seeds, `createDeal`, `dealFromRow`)
- Modify: `lib/data/repositories/reservation_repository.dart` (`_copyWithSlots` → `Deal.copyWith`)
- Modify: `lib/ui/split_board/widgets/deal_card.dart`, `lib/ui/split_board/deal_details_screen.dart` (badges: six cases, no `fillingFast`)
- Modify: `lib/ui/split_board/split_board_viewmodel.dart` (hide finished deals)
- Test: `test/models/deal_status_test.dart` (create)

- [ ] **Step 1: Write the failing tests**

Create `test/models/deal_status_test.dart`:

```dart
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:flutter_test/flutter_test.dart';

Deal deal({
  int totalSlots = 4,
  required int availableSlots,
  int paidCount = 0,
  int collectedCount = 0,
  DateTime? purchasedAt,
  DateTime? cancelledAt,
}) {
  return Deal(
    id: 'd',
    hubId: 'h',
    title: 'Rice',
    category: DealCategory.grocery,
    totalPrice: 400,
    amount: 20,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: totalSlots,
    pickupLocation: 'Lobby',
    paidCount: paidCount,
    collectedCount: collectedCount,
    purchasedAt: purchasedAt,
    cancelledAt: cancelledAt,
  );
}

void main() {
  final now = DateTime(2026, 7, 16);

  test('slots still free is open', () {
    expect(deal(availableSlots: 2).status, DealStatus.open);
  });

  test('every claimed slot is a participant', () {
    expect(deal(totalSlots: 4, availableSlots: 1).participantCount, 3);
  });

  test('no slots left, not everyone paid, is full', () {
    expect(deal(availableSlots: 0, paidCount: 3).status, DealStatus.full);
  });

  test('no slots left and everyone paid is ready to purchase', () {
    expect(
      deal(availableSlots: 0, paidCount: 4).status,
      DealStatus.readyToPurchase,
    );
  });

  test('bought is ready for pickup, however many have paid', () {
    expect(
      deal(availableSlots: 0, paidCount: 1, purchasedAt: now).status,
      DealStatus.readyForPickup,
    );
  });

  test('bought and everyone collected is completed', () {
    expect(
      deal(
        availableSlots: 0,
        paidCount: 4,
        collectedCount: 4,
        purchasedAt: now,
      ).status,
      DealStatus.completed,
    );
  });

  test('cancelled beats everything else', () {
    expect(
      deal(
        availableSlots: 0,
        paidCount: 4,
        collectedCount: 4,
        purchasedAt: now,
        cancelledAt: now,
      ).status,
      DealStatus.cancelled,
    );
  });

  // The reason status is derived rather than stored: no code path makes this
  // happen, and it still has to be right.
  test('a student leaving a ready-to-purchase deal reopens it', () {
    final ready = deal(availableSlots: 0, paidCount: 4);
    expect(ready.status, DealStatus.readyToPurchase);

    final afterCancel = ready.copyWith(availableSlots: 1, paidCount: 3);
    expect(afterCancel.status, DealStatus.open);
  });

  // Goods that were never bought cannot be reported as collected.
  test('collected without a purchase is not completed', () {
    expect(
      deal(availableSlots: 0, paidCount: 4, collectedCount: 4).status,
      DealStatus.readyToPurchase,
    );
  });

  test('a deal with nobody in it is not completed', () {
    expect(
      deal(totalSlots: 4, availableSlots: 4, purchasedAt: now).status,
      DealStatus.readyForPickup,
    );
  });

  group('filling fast', () {
    test('an open deal with a quarter of its slots left is filling fast', () {
      final d = deal(totalSlots: 8, availableSlots: 2);
      expect(d.isFillingFast, isTrue);
      expect(d.statusLabel, 'Filling fast');
    });

    test('more than a quarter left is just open', () {
      final d = deal(totalSlots: 8, availableSlots: 3);
      expect(d.isFillingFast, isFalse);
      expect(d.statusLabel, 'Open');
    });

    test('a full deal is never filling fast', () {
      final d = deal(totalSlots: 8, availableSlots: 0);
      expect(d.isFillingFast, isFalse);
      expect(d.statusLabel, 'Full');
    });
  });

  group('what the host is holding', () {
    // The host's own slot is marked paid at creation -- they cannot pay
    // themselves -- so it is not money they owe back.
    test('the host is not counted as a student who paid', () {
      final d = deal(totalSlots: 4, availableSlots: 0, paidCount: 1);
      expect(d.studentsWhoPaid, 0);
      expect(d.amountHeld, 0);
    });

    test('money held is the students who paid, at the per-share price', () {
      final d = deal(totalSlots: 4, availableSlots: 0, paidCount: 3);
      expect(d.studentsWhoPaid, 2);
      expect(d.amountHeld, 200); // 400 / 4 slots = 100 each
    });
  });

  test('finished deals are the ones the board hides', () {
    expect(DealStatus.completed.isFinished, isTrue);
    expect(DealStatus.cancelled.isFinished, isTrue);
    expect(DealStatus.open.isFinished, isFalse);
    expect(DealStatus.readyForPickup.isFinished, isFalse);
  });
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `flutter test test/models/deal_status_test.dart`
Expected: compile errors — `paidCount` is not a parameter, `participantCount`,
`isFillingFast`, `statusLabel`, `studentsWhoPaid`, `amountHeld`, `isFinished`,
`copyWith` are not defined, `DealStatus.readyToPurchase` does not exist.

- [ ] **Step 3: Rewrite `DealStatus` in `lib/models/deal.dart`**

Replace the whole enum (delete `fillingFast`):

```dart
enum DealStatus {
  open('Open'),
  full('Full'),
  readyToPurchase('Ready to purchase'),
  readyForPickup('Ready for pickup'),
  completed('Completed'),
  cancelled('Cancelled');

  const DealStatus(this.label);

  final String label;

  /// Completed and cancelled deals are not open business. The Split Board hides
  /// them unless they are asked for by name.
  bool get isFinished =>
      this == DealStatus.completed || this == DealStatus.cancelled;
}
```

- [ ] **Step 4: Give `Deal` the facts and the derivation**

In `lib/models/deal.dart`, delete `required this.status,` from the constructor
and `final DealStatus status;` from the fields. Add to the constructor:

```dart
    this.purchasedAt,
    this.cancelledAt,
    this.paidCount = 0,
    this.collectedCount = 0,
```

Add the fields and the derivation, next to `costSplit` and `physicalShare`:

```dart
  /// The host has bought the goods. Set by mark_purchased; never cleared.
  final DateTime? purchasedAt;

  /// The host called the deal off. Set by cancel_deal; never cleared.
  final DateTime? cancelledAt;

  /// How many of the students in this deal have handed the host their share,
  /// and how many have taken their goods away. Both come from deal_feed.
  final int paidCount;
  final int collectedCount;

  /// Every claimed slot is a student in the buy. The reserve/cancel RPCs move
  /// available_slots and the reservation rows together in one transaction, so
  /// this cannot drift — and storing it separately would be a second copy of a
  /// number that already exists.
  int get participantCount => totalSlots - availableSlots;

  /// Derived, never stored. The column this replaces was updated by nothing, so
  /// a full deal still showed an "Open" badge. Here there is no second copy to
  /// keep in step: a student leaving a ready-to-purchase deal reopens it with no
  /// code path written to make that happen.
  DealStatus get status {
    if (cancelledAt != null) return DealStatus.cancelled;

    if (purchasedAt != null) {
      // Purchase gates both, so goods that were never bought cannot be reported
      // as collected.
      return participantCount > 0 && collectedCount >= participantCount
          ? DealStatus.completed
          : DealStatus.readyForPickup;
    }

    if (availableSlots == 0) {
      return participantCount > 0 && paidCount >= participantCount
          ? DealStatus.readyToPurchase
          : DealStatus.full;
    }

    return DealStatus.open;
  }

  /// A label on an open deal that is nearly full, not a state of its own.
  bool get isFillingFast =>
      status == DealStatus.open && availableSlots * 4 <= totalSlots;

  /// What the badge reads.
  String get statusLabel => isFillingFast ? 'Filling fast' : status.label;

  /// The host's own slot is marked paid the moment the deal exists — they
  /// cannot pay themselves — so it is not money they are holding for anyone.
  int get studentsWhoPaid => (paidCount - 1).clamp(0, totalSlots);

  /// What the host would have to hand back if they cancelled now.
  double get amountHeld => studentsWhoPaid * pricePerShare;

  Deal copyWith({
    int? availableSlots,
    DateTime? purchasedAt,
    DateTime? cancelledAt,
    int? paidCount,
    int? collectedCount,
  }) {
    return Deal(
      id: id,
      hubId: hubId,
      title: title,
      description: description,
      createdBy: createdBy,
      hostName: hostName,
      category: category,
      totalPrice: totalPrice,
      amount: amount,
      unit: unit,
      availableSlots: availableSlots ?? this.availableSlots,
      totalSlots: totalSlots,
      pickupLocation: pickupLocation,
      closesAt: closesAt,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      paidCount: paidCount ?? this.paidCount,
      collectedCount: collectedCount ?? this.collectedCount,
    );
  }
```

`copyWith` only takes the fields the lifecycle changes, and cannot clear
`purchasedAt` or `cancelledAt` — nothing in the app ever un-buys or un-cancels a
deal.

- [ ] **Step 5: Run the model tests**

Run: `flutter test test/models/deal_status_test.dart`
Expected: PASS (all of them).

- [ ] **Step 6: Fix every call site that passed `status:`**

`flutter analyze` now fails. Work through it:

**`lib/data/repositories/deal_repository.dart`:**
- Delete `_dealStatusFromValue` and `_statusValue` entirely — status is never
  parsed from or written to the database again.
- In `dealFromRow`, delete the `status:` line and add:

```dart
  final purchasedAt = row['purchased_at'] as String?;
  final cancelledAt = row['cancelled_at'] as String?;
```

```dart
    purchasedAt:
        purchasedAt == null ? null : DateTime.parse(purchasedAt).toLocal(),
    cancelledAt:
        cancelledAt == null ? null : DateTime.parse(cancelledAt).toLocal(),
    // Absent on the raw deals row an insert returns; deal_feed carries them.
    paidCount: (row['paid_count'] as num?)?.toInt() ?? 0,
    collectedCount: (row['collected_count'] as num?)?.toInt() ?? 0,
```

- In `createDeal` (Supabase), delete `'status': _statusValue(DealStatus.open),`
  from the insert map.
- In `MockDealRepository.createDeal`, replace `status: DealStatus.open,` with
  `paidCount: 1,` — a new deal has exactly one participant, the host, and the
  host's slot is paid from the moment it exists.
- In the mock's seeded deals, delete every `status:` line and give the counts
  that produce the status the seed used to claim. Use exactly these:
  - `colon-rice` (3 of 5 free, was open): add nothing — it is Open.
  - `colon-water` (2 of 4 free, was fillingFast): change `availableSlots: 2` to
    `availableSlots: 1`, so it is genuinely nearly full and the badge says
    "Filling fast" because it *is* filling fast.
  - `colon-detergent` (0 of 3 free, was full): add `paidCount: 2,` — full, and
    still waiting on one student's money.
  - `magallanes-eggs` (1 of 3 free, was fillingFast): add nothing — 1 of 3 free
    is a third, not a quarter, so this one is plain Open. That is correct: the
    old `fillingFast` here was a lie the seed told.
  - `magallanes-coffee` (4 of 6 free, was open): add nothing — Open.

**`lib/data/repositories/reservation_repository.dart`:**
Delete `_copyWithSlots` and use `Deal.copyWith` instead:

```dart
    _deal = _deal.copyWith(availableSlots: _deal.availableSlots - 1);
```
```dart
    _deal = _deal.copyWith(availableSlots: _deal.availableSlots + 1);
```

**`lib/ui/split_board/widgets/deal_card.dart`:**
The badge must show the derived label, so it takes the deal, not the status.
Change `_StatusBadge({required this.status})` to `_StatusBadge({required this.deal})`,
`final Deal deal;`, and its call site at line ~77 to `_StatusBadge(deal: deal)`.
Inside `build`, use `deal.statusLabel` as the text and colour on the badge tone:

```dart
  _BadgeColors _statusColors(ThemeData theme, Deal deal) {
    if (deal.isFillingFast) {
      return _BadgeColors(
        background: theme.colorScheme.tertiaryContainer,
        foreground: theme.colorScheme.onTertiaryContainer,
      );
    }
    return switch (deal.status) {
      DealStatus.open => _BadgeColors(
        background: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
      ),
      DealStatus.full ||
      DealStatus.readyToPurchase => _BadgeColors(
        background: theme.colorScheme.tertiaryContainer,
        foreground: theme.colorScheme.onTertiaryContainer,
      ),
      DealStatus.readyForPickup => _BadgeColors(
        background: theme.colorScheme.secondaryContainer,
        foreground: theme.colorScheme.onSecondaryContainer,
      ),
      DealStatus.completed => _BadgeColors(
        background: theme.colorScheme.surfaceContainerHighest,
        foreground: theme.colorScheme.onSurfaceVariant,
      ),
      DealStatus.cancelled => _BadgeColors(
        background: theme.colorScheme.errorContainer,
        foreground: theme.colorScheme.onErrorContainer,
      ),
    };
  }
```

**`lib/ui/split_board/deal_details_screen.dart`:**
Same change to its own `_StatusBadge`: take `Deal deal`, print `deal.statusLabel`,
and cover six statuses with the screen's hand-picked palette:

```dart
    final (background, foreground) = deal.isFillingFast
        ? (const Color(0xFFFDECC8), const Color(0xFF6B4A00))
        : switch (deal.status) {
            DealStatus.open => (
              const Color(0xFFDCEFE3),
              const Color(0xFF173E28),
            ),
            DealStatus.full => (
              const Color(0xFFFDECC8),
              const Color(0xFF6B4A00),
            ),
            DealStatus.readyToPurchase => (
              const Color(0xFFDDE7F7),
              const Color(0xFF1B3A66),
            ),
            DealStatus.readyForPickup => (
              const Color(0xFFDDE7F7),
              const Color(0xFF1B3A66),
            ),
            DealStatus.completed => (
              const Color(0xFFE6E6E1),
              const Color(0xFF3D3D38),
            ),
            DealStatus.cancelled => (
              const Color(0xFFF3D6D6),
              const Color(0xFF6B1D1D),
            ),
          };
```

Its call site at line ~64 becomes `_StatusBadge(deal: deal)`.

**`lib/ui/split_board/split_board_viewmodel.dart`:**
In `filteredDeals`, a finished deal is hidden unless asked for by name:

```dart
      // Completed and cancelled deals are not open business. They stay
      // reachable through the filter, but they do not clutter the board.
      final matchesStatus = _statusFilter == null
          ? !deal.status.isFinished
          : deal.status == _statusFilter;
```

- [ ] **Step 7: Run the whole suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass, `No issues found!`

Existing tests that asserted `DealStatus.fillingFast` or passed `status:` must be
updated to the new model — that is expected work, not a signal something is wrong.

**`test/ui/split_board/split_board_viewmodel_test.dart` needs two changes.**
`_StubDeal extends Deal` and passes `super.status = DealStatus.open`, which no
longer exists — delete that parameter and add
`super.paidCount = 0, super.collectedCount = 0, super.purchasedAt, super.cancelledAt`
so the stubs can express a lifecycle. It also hard-codes `availableSlots: 1,
totalSlots: 4` — one slot free of four is a quarter, so every stub would now
render **"Filling fast"**. Change it to `availableSlots: 2`, which keeps those
tests about sorting and filtering rather than accidentally about badges.

`test/ui/split_board/deal_card_test.dart` will have the same `status:` breakage.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: derive a deal's status from its facts instead of storing it"
```

---

### Task 2: `Reservation` carries paid and collected

**Files:**
- Modify: `lib/models/reservation.dart`
- Modify: `lib/data/repositories/reservation_repository.dart` (`_reservationFromRow`)
- Test: `test/models/reservation_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/models/reservation_test.dart`:

```dart
  test('a reservation knows whether it is paid and collected', () {
    final unpaid = Reservation(
      dealId: 'd',
      userId: 'u',
      reservedAt: DateTime(2026, 7, 16),
    );
    expect(unpaid.hasPaid, isFalse);
    expect(unpaid.hasCollected, isFalse);

    final settled = Reservation(
      dealId: 'd',
      userId: 'u',
      reservedAt: DateTime(2026, 7, 16),
      paidAt: DateTime(2026, 7, 16),
      collectedAt: DateTime(2026, 7, 17),
    );
    expect(settled.hasPaid, isTrue);
    expect(settled.hasCollected, isTrue);
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/models/reservation_test.dart`
Expected: compile error — `paidAt` is not a named parameter.

- [ ] **Step 3: Add the fields**

In `lib/models/reservation.dart`, add to the constructor `this.paidAt,` and
`this.collectedAt,`, then:

```dart
  /// When this student handed the host their share. The host's own slot is paid
  /// from the moment the deal exists — they cannot pay themselves.
  final DateTime? paidAt;

  /// When this student took their goods away. Only ever set after the host has
  /// bought them.
  final DateTime? collectedAt;

  bool get hasPaid => paidAt != null;
  bool get hasCollected => collectedAt != null;
```

- [ ] **Step 4: Map them from the view**

In `SupabaseReservationRepository._reservationFromRow`:

```dart
    final paidAt = row['paid_at'] as String?;
    final collectedAt = row['collected_at'] as String?;
```

```dart
      paidAt: paidAt == null ? null : DateTime.parse(paidAt).toLocal(),
      collectedAt:
          collectedAt == null ? null : DateTime.parse(collectedAt).toLocal(),
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/models/reservation_test.dart && flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: a reservation records when it was paid and collected"
```

---

### Task 3: The migration

Nothing in this task is exercised by `flutter test` — it is proven in Task 8 by
running SQL against the live project, exactly as the reservation RPCs were.

**Files:**
- Create: `supabase/migrations/20260716000000_add_deal_lifecycle.sql`

- [ ] **Step 1: Write the migration**

```sql
-- A deal's status was a column nothing ever updated. reserve_slot moved
-- available_slots and never touched status, so a full deal still showed an
-- "Open" badge, and every row in this database says 'open'.
--
-- The fix is to stop storing it. This migration stores the facts a status is a
-- reading of -- who paid, who collected, whether the host bought it or called it
-- off -- and Dart derives the status from them (see Deal.status). There is no
-- second copy to keep in step.

-- 1. The facts.

alter table public.deals
  add column if not exists purchased_at timestamptz,
  add column if not exists cancelled_at timestamptz;

alter table public.deal_reservations
  add column if not exists paid_at timestamptz,
  add column if not exists collected_at timestamptz;

-- 2. The host's slot is paid from the moment the deal exists.
--
-- They front the money and collect it; they cannot pay themselves. Were this
-- left null, "everyone has paid" could never become true and a deal could never
-- reach Ready to Purchase.

create or replace function public.reserve_host_slot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  insert into public.deal_reservations (deal_id, user_id, paid_at)
  values (new.id, new.created_by, now());
  return new;
end;
$fn$;

update public.deal_reservations r
set paid_at = coalesce(r.paid_at, r.reserved_at)
from public.deals d
where d.id = r.deal_id and d.created_by = r.user_id;

-- 3. The views expose the facts, and the status column goes.
--
-- The two existing RPCs return public.deals, whose rows carry no paid or
-- collected counts -- a Dart Deal built from one would report paidCount: 0 and
-- the badge would fall back to "Full" the moment the host marked someone paid.
-- Every RPC below returns the deal_feed row instead, as jsonb.
--
-- jsonb rather than `returns public.deal_feed`: a function whose return type is
-- a view's rowtype pins that view in place, and deal_feed has already had to be
-- dropped and recreated twice (removing a column requires it).
--
-- Changing a function's return type needs DROP, not CREATE OR REPLACE. Dropping
-- them here also frees the view to be replaced.

drop function if exists public.reserve_slot(uuid);
drop function if exists public.cancel_reservation(uuid);

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
  d.closes_at,
  d.created_at,
  d.purchased_at,
  d.cancelled_at,
  p.display_name as host_name,
  c.paid_count,
  c.collected_count
from public.deals d
left join public.profiles p on p.user_id = d.created_by
left join lateral (
  select
    count(r.paid_at)      as paid_count,
    count(r.collected_at) as collected_count
  from public.deal_reservations r
  where r.deal_id = d.id
) c on true
-- A view runs with its owner's rights and ignores RLS on the tables underneath,
-- so the view itself is the security boundary. Without this, any signed-in
-- student could read every hub's deals. Added 2026-07-14; keep it.
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id
    and m.user_id = (select auth.uid())
);

grant select on public.deal_feed to authenticated;

-- Nothing reads it, and every row holds the default. No information is lost.
-- Dropping the column drops deals_status_check with it.
alter table public.deals drop column status;

-- Who is in a deal, and where each of them stands.
create or replace view public.deal_participants as
select
  r.deal_id,
  r.user_id,
  r.reserved_at,
  r.paid_at,
  r.collected_at,
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

-- 4. One shape for every RPC to hand back.
--
-- auth.uid() still resolves to the caller inside a security definer function, so
-- deal_feed's hub-membership filter applies to the caller, not the owner.

create or replace function public.deal_feed_row(p_deal_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $fn$
  select to_jsonb(f) from public.deal_feed f where f.id = p_deal_id;
$fn$;

-- 5. Claiming and releasing a slot, rebuilt to return the feed row and to
--    respect the two new ends of a deal's life.

create or replace function public.reserve_slot(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_updated int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from public.hub_memberships m
    where m.hub_id = v_deal.hub_id and m.user_id = v_user_id
  ) then
    raise exception 'Deal not available.' using errcode = '42501';
  end if;

  -- Once the host has bought the goods or called the deal off, the count they
  -- spent money against is final. Nobody else joins.
  if v_deal.cancelled_at is not null or v_deal.purchased_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- The primary key rejects a second claim by the same student (23505).
  insert into public.deal_reservations (deal_id, user_id)
  values (p_deal_id, v_user_id);

  -- Concurrent callers serialise on this row. Under READ COMMITTED the loser
  -- re-evaluates the WHERE after the winner commits, finds available_slots = 0,
  -- updates nothing, and the whole transaction (including the insert above)
  -- rolls back.
  --
  -- Checked with row_count, not `returning * into v_deal`: v_deal is already
  -- populated from the select above, and plpgsql leaves it untouched when a
  -- RETURNING matches no rows -- so the null check would never fire.
  update public.deals
  set available_slots = available_slots - 1
  where id = p_deal_id and available_slots > 0;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'Deal is full.' using errcode = 'P0001';
  end if;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.cancel_reservation(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_reservation public.deal_reservations;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  -- Everyone else is relying on the host. They cannot quietly slip out; to get
  -- out they cancel the whole deal.
  if v_deal.created_by = v_user_id then
    raise exception 'Host cannot cancel.' using errcode = 'P0003';
  end if;

  if v_deal.cancelled_at is not null or v_deal.purchased_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- The deadline is the commitment point: past it the host is about to spend
  -- real money, and the count they are spending against must be final.
  if v_deal.closes_at is not null and v_deal.closes_at <= now() then
    raise exception 'Deadline passed.' using errcode = 'P0004';
  end if;

  select * into v_reservation
  from public.deal_reservations
  where deal_id = p_deal_id and user_id = v_user_id;

  if v_reservation.deal_id is null then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  -- Walking away after paying would leave the host holding money they owe back,
  -- with no record that they owe it. Talk to the host; they unmark the payment.
  if v_reservation.paid_at is not null then
    raise exception 'Already paid.' using errcode = 'P0011';
  end if;

  delete from public.deal_reservations
  where deal_id = p_deal_id and user_id = v_user_id;

  update public.deals
  set available_slots = available_slots + 1
  where id = p_deal_id and available_slots < total_slots;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

-- 6. The host's four levers.
--
-- Every one of them checks created_by = auth.uid() here, in Postgres, and not in
-- Dart. A client-side permission check is a suggestion, not a control: a student
-- who could mark themselves paid could push a deal to Ready to Purchase and send
-- the host out to spend money on a promise.
--
-- P0012 rather than the canonical 42501, because ReservationRepository already
-- maps 42501 to "You can only reserve slots in your own hub", and one code
-- cannot carry two meanings in one message table.

create or replace function public.set_participant_paid(
  p_deal_id uuid,
  p_user_id uuid,
  p_paid boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_updated int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- Unmarking is allowed: a host who mis-taps must be able to take it back, and
  -- a student cannot leave a deal they are marked paid for until they do.
  update public.deal_reservations
  set paid_at = case when p_paid then now() else null end
  where deal_id = p_deal_id and user_id = p_user_id;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.set_participant_collected(
  p_deal_id uuid,
  p_user_id uuid,
  p_collected boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
  v_updated int;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  -- Nobody collects goods that do not exist yet.
  if v_deal.purchased_at is null then
    raise exception 'Goods not bought yet.' using errcode = 'P0007';
  end if;

  update public.deal_reservations
  set collected_at = case when p_collected then now() else null end
  where deal_id = p_deal_id and user_id = p_user_id;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'No slot held.' using errcode = 'P0005';
  end if;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.mark_purchased(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Deal is closed.' using errcode = 'P0006';
  end if;

  if v_deal.purchased_at is not null then
    raise exception 'Already bought.' using errcode = 'P0008';
  end if;

  -- Deliberately does NOT require the deal to be full or fully paid. A host who
  -- bought early has bought early; the app's job is to record that, not argue.
  update public.deals
  set purchased_at = now()
  where id = p_deal_id;

  -- The host is standing there holding the goods, so their own share is
  -- collected. Otherwise they would have to tick themselves off a list to
  -- confirm they had handed themselves their own rice.
  update public.deal_reservations
  set collected_at = now()
  where deal_id = p_deal_id and user_id = v_deal.created_by;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

create or replace function public.cancel_deal(p_deal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_user_id uuid := (select auth.uid());
  v_deal public.deals;
begin
  if v_user_id is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  select * into v_deal from public.deals where id = p_deal_id;

  if v_deal.id is null then
    raise exception 'Deal not found.' using errcode = 'P0002';
  end if;

  if v_deal.created_by is distinct from v_user_id then
    raise exception 'Only the host can do that.' using errcode = 'P0012';
  end if;

  if v_deal.cancelled_at is not null then
    raise exception 'Already cancelled.' using errcode = 'P0009';
  end if;

  -- Completed, by the same rule Dart uses: bought, and nobody left to collect.
  -- The goods are gone; there is nothing left to call off.
  if v_deal.purchased_at is not null and not exists (
    select 1
    from public.deal_reservations r
    where r.deal_id = p_deal_id and r.collected_at is null
  ) then
    raise exception 'Deal is completed.' using errcode = 'P0010';
  end if;

  update public.deals
  set cancelled_at = now()
  where id = p_deal_id;

  return public.deal_feed_row(p_deal_id);
end;
$fn$;

grant execute on function public.reserve_slot(uuid) to authenticated;
grant execute on function public.cancel_reservation(uuid) to authenticated;
grant execute on function public.set_participant_paid(uuid, uuid, boolean) to authenticated;
grant execute on function public.set_participant_collected(uuid, uuid, boolean) to authenticated;
grant execute on function public.mark_purchased(uuid) to authenticated;
grant execute on function public.cancel_deal(uuid) to authenticated;
```

- [ ] **Step 2: Commit**

The user applies it to Supabase and it is proven in Task 8. Do not ask them to
run it now — it lands with the rest of the card.

```bash
git add supabase/migrations/20260716000000_add_deal_lifecycle.sql
git commit -m "feat: store the facts a deal's status is a reading of"
```

---

### Task 4: The repository speaks the lifecycle

All four host actions live on `ReservationRepository`. They belong to the same
mock state as `reserveSlot` — one deal, one set of holders, one set of payments —
and splitting them across two repositories would mean two mocks fighting over one
deal.

**Files:**
- Modify: `lib/data/repositories/reservation_repository.dart`
- Test: `test/data/repositories/reservation_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/data/repositories/reservation_repository_test.dart`:

```dart
  group('the host marks the deal along', () {
    late MockReservationRepository repository;

    Deal hostedDeal() => Deal(
      id: 'd',
      hubId: 'h',
      createdBy: 'host',
      title: 'Rice',
      category: DealCategory.grocery,
      totalPrice: 400,
      amount: 20,
      unit: DealUnit.kg,
      availableSlots: 3,
      totalSlots: 4,
      pickupLocation: 'Lobby',
      paidCount: 1,
    );

    setUp(() {
      repository = MockReservationRepository(
        deal: hostedDeal(),
        currentUserId: 'host',
      );
    });

    test('marking every student paid makes a full deal ready to purchase', () async {
      await repository.reserveSlotFor('ana');
      await repository.reserveSlotFor('bea');
      await repository.reserveSlotFor('cy');
      expect(repository.deal.status, DealStatus.full);

      await repository.setPaid('d', 'ana', paid: true);
      await repository.setPaid('d', 'bea', paid: true);
      final deal = await repository.setPaid('d', 'cy', paid: true);

      expect(deal.status, DealStatus.readyToPurchase);
    });

    test('unmarking a payment takes it back out of ready to purchase', () async {
      await repository.reserveSlotFor('ana');
      await repository.reserveSlotFor('bea');
      await repository.reserveSlotFor('cy');
      await repository.setPaid('d', 'ana', paid: true);
      await repository.setPaid('d', 'bea', paid: true);
      await repository.setPaid('d', 'cy', paid: true);

      final deal = await repository.setPaid('d', 'cy', paid: false);
      expect(deal.status, DealStatus.full);
    });

    test('buying makes it ready for pickup and collects the host share', () async {
      final deal = await repository.markPurchased('d');

      expect(deal.status, DealStatus.readyForPickup);
      final participants = await repository.getParticipants('d');
      final host = participants.firstWhere((p) => p.isHost);
      expect(host.hasCollected, isTrue);
    });

    test('goods cannot be collected before they are bought', () async {
      await repository.reserveSlotFor('ana');

      expect(
        () => repository.setCollected('d', 'ana', collected: true),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('the last collection completes the deal', () async {
      await repository.reserveSlotFor('ana');
      await repository.markPurchased('d');

      final deal = await repository.setCollected('d', 'ana', collected: true);
      expect(deal.status, DealStatus.completed);
    });

    test('cancelling ends the deal', () async {
      final deal = await repository.cancelDeal('d');
      expect(deal.status, DealStatus.cancelled);
    });

    test('a completed deal cannot be cancelled', () async {
      await repository.reserveSlotFor('ana');
      await repository.markPurchased('d');
      await repository.setCollected('d', 'ana', collected: true);

      expect(
        () => repository.cancelDeal('d'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('a student who has paid cannot walk away', () async {
      await repository.reserveSlotFor('ana');
      await repository.setPaid('d', 'ana', paid: true);

      expect(
        () => repository.cancelReservationFor('ana'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('a student who is not the host cannot mark anyone paid', () async {
      final ana = MockReservationRepository(
        deal: hostedDeal(),
        currentUserId: 'ana',
      );

      expect(
        () => ana.setPaid('d', 'ana', paid: true),
        throwsA(isA<ReservationFailure>()),
      );
      expect(
        () => ana.markPurchased('d'),
        throwsA(isA<ReservationFailure>()),
      );
      expect(
        () => ana.cancelDeal('d'),
        throwsA(isA<ReservationFailure>()),
      );
    });
  });
```

The mock needs `reserveSlotFor` / `cancelReservationFor` test seams so one
repository instance can stand in for several students — the real
`reserveSlot()` acts as `currentUserId`, and a test that needs three students in
one deal cannot use three separate mocks without three separate deals.

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/data/repositories/reservation_repository_test.dart`
Expected: compile errors — `setPaid`, `setCollected`, `markPurchased`,
`cancelDeal`, `reserveSlotFor`, `cancelReservationFor` are not defined.

- [ ] **Step 3: Extend the contract**

In `lib/data/repositories/reservation_repository.dart`, add to
`abstract class ReservationRepository`:

```dart
  /// The host's four levers. Each returns the deal as it now stands, so the
  /// caller never has to guess the new status.
  ///
  /// Host-only, enforced in Postgres — a student who could mark themselves paid
  /// could send the host out to spend money on a promise.
  Future<Deal> setPaid(String dealId, String userId, {required bool paid});

  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  });

  Future<Deal> markPurchased(String dealId);

  Future<Deal> cancelDeal(String dealId);
```

- [ ] **Step 4: Extend the gateway and the Supabase implementation**

Add to `abstract class SupabaseReservationGateway`:

```dart
  Future<Map<String, dynamic>> setParticipantPaid(
    String dealId,
    String userId,
    bool paid,
  );

  Future<Map<String, dynamic>> setParticipantCollected(
    String dealId,
    String userId,
    bool collected,
  );

  Future<Map<String, dynamic>> markPurchased(String dealId);

  Future<Map<String, dynamic>> cancelDeal(String dealId);
```

In `PostgrestSupabaseReservationGateway`:

```dart
  @override
  Future<Map<String, dynamic>> setParticipantPaid(
    String dealId,
    String userId,
    bool paid,
  ) async {
    final row = await _client.rpc(
      'set_participant_paid',
      params: {'p_deal_id': dealId, 'p_user_id': userId, 'p_paid': paid},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> setParticipantCollected(
    String dealId,
    String userId,
    bool collected,
  ) async {
    final row = await _client.rpc(
      'set_participant_collected',
      params: {
        'p_deal_id': dealId,
        'p_user_id': userId,
        'p_collected': collected,
      },
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> markPurchased(String dealId) async {
    final row = await _client.rpc(
      'mark_purchased',
      params: {'p_deal_id': dealId},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> cancelDeal(String dealId) async {
    final row = await _client.rpc(
      'cancel_deal',
      params: {'p_deal_id': dealId},
    );
    return Map<String, dynamic>.from(row as Map);
  }
```

In `SupabaseReservationRepository`:

```dart
  @override
  Future<Deal> setPaid(
    String dealId,
    String userId, {
    required bool paid,
  }) async {
    try {
      return dealFromRow(
        await _gateway.setParticipantPaid(dealId, userId, paid),
      );
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  }) async {
    try {
      return dealFromRow(
        await _gateway.setParticipantCollected(dealId, userId, collected),
      );
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> markPurchased(String dealId) async {
    try {
      return dealFromRow(await _gateway.markPurchased(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> cancelDeal(String dealId) async {
    try {
      return dealFromRow(await _gateway.cancelDeal(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }
```

Add the new codes to `_messageFor`, keeping the existing ones:

```dart
      'P0006' => 'This deal is closed.',
      'P0007' => 'The goods have not been bought yet.',
      'P0008' => 'You have already marked this bought.',
      'P0009' => 'This deal is already cancelled.',
      'P0010' => 'This deal is finished, so it cannot be cancelled.',
      'P0011' =>
        'You have already paid for this slot. Ask the host before you pull out.',
      'P0012' => 'Only the host can do that.',
```

- [ ] **Step 5: Extend the mock so it obeys the same rules**

`MockReservationRepository` must refuse for the same reasons the database does,
or the ViewModel tests pass for reasons production would not.

```dart
class MockReservationRepository implements ReservationRepository {
  MockReservationRepository({required Deal deal, required this.currentUserId})
    : _deal = deal,
      _holders = {
        // Every deal has its host in it, exactly as the trigger guarantees.
        if (deal.createdBy != null) deal.createdBy!,
      },
      // The host's slot is paid from the moment the deal exists.
      _paid = {if (deal.createdBy != null) deal.createdBy!},
      _collected = {};

  Deal _deal;
  final Set<String> _holders;
  final Set<String> _paid;
  final Set<String> _collected;
  final String currentUserId;

  Deal get deal => _deal;

  /// Test seam: stand in for another student. reserveSlot() always acts as
  /// currentUserId, and a deal with three students in it cannot be built from
  /// three separate mocks — they would each hold a different deal.
  Future<Deal> reserveSlotFor(String userId) async {
    if (_holders.contains(userId)) {
      throw const ReservationFailure('You already have a slot in this deal.');
    }
    if (_deal.availableSlots == 0) {
      throw const ReservationFailure('This deal just filled up.');
    }
    _holders.add(userId);
    return _sync(availableSlots: _deal.availableSlots - 1);
  }

  Future<Deal> cancelReservationFor(String userId) async {
    if (userId == _deal.createdBy) {
      throw const ReservationFailure(
        'You are organising this buy, so your slot cannot be cancelled.',
      );
    }
    if (_paid.contains(userId)) {
      throw const ReservationFailure(
        'You have already paid for this slot. Ask the host before you pull out.',
      );
    }
    if (!_holders.remove(userId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }
    _collected.remove(userId);
    return _sync(availableSlots: _deal.availableSlots + 1);
  }

  /// Test seam: record a payment without being the host, so a student's own view
  /// of a deal they have already paid for can be built. setPaid() refuses a
  /// non-host caller, exactly as the database does.
  Future<Deal> setPaidAsHost(String userId) async {
    _paid.add(userId);
    return _sync();
  }

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
            paidAt: _paid.contains(userId) ? DateTime(2026, 7, 14) : null,
            collectedAt:
                _collected.contains(userId) ? DateTime(2026, 7, 15) : null,
          ),
        )
        .toList();
  }

  @override
  Future<Deal> reserveSlot(String dealId) async {
    if (_deal.cancelledAt != null || _deal.purchasedAt != null) {
      throw const ReservationFailure('This deal is closed.');
    }
    return reserveSlotFor(currentUserId);
  }

  @override
  Future<Deal> cancelReservation(String dealId) async {
    if (_deal.cancelledAt != null || _deal.purchasedAt != null) {
      throw const ReservationFailure('This deal is closed.');
    }
    final closesAt = _deal.closesAt;
    if (closesAt != null && !closesAt.isAfter(DateTime.now())) {
      throw const ReservationFailure(
        'The deadline has passed, so slots are locked.',
      );
    }
    return cancelReservationFor(currentUserId);
  }

  @override
  Future<Deal> setPaid(
    String dealId,
    String userId, {
    required bool paid,
  }) async {
    _requireHost();
    _requireOpen();
    if (!_holders.contains(userId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }
    paid ? _paid.add(userId) : _paid.remove(userId);
    return _sync();
  }

  @override
  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  }) async {
    _requireHost();
    _requireOpen();
    if (_deal.purchasedAt == null) {
      throw const ReservationFailure('The goods have not been bought yet.');
    }
    if (!_holders.contains(userId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }
    collected ? _collected.add(userId) : _collected.remove(userId);
    return _sync();
  }

  @override
  Future<Deal> markPurchased(String dealId) async {
    _requireHost();
    _requireOpen();
    if (_deal.purchasedAt != null) {
      throw const ReservationFailure('You have already marked this bought.');
    }
    // The host is holding the goods, so their own share is collected.
    final host = _deal.createdBy;
    if (host != null) _collected.add(host);
    return _sync(purchasedAt: DateTime(2026, 7, 16));
  }

  @override
  Future<Deal> cancelDeal(String dealId) async {
    _requireHost();
    if (_deal.cancelledAt != null) {
      throw const ReservationFailure('This deal is already cancelled.');
    }
    if (_deal.status == DealStatus.completed) {
      throw const ReservationFailure(
        'This deal is finished, so it cannot be cancelled.',
      );
    }
    return _sync(cancelledAt: DateTime(2026, 7, 16));
  }

  void _requireHost() {
    if (currentUserId != _deal.createdBy) {
      throw const ReservationFailure('Only the host can do that.');
    }
  }

  void _requireOpen() {
    if (_deal.cancelledAt != null) {
      throw const ReservationFailure('This deal is closed.');
    }
  }

  /// The counts on a Deal come from deal_feed, which recounts the reservation
  /// rows on every read. The mock recounts too, rather than tracking a second
  /// copy that could drift from the sets above.
  Deal _sync({
    int? availableSlots,
    DateTime? purchasedAt,
    DateTime? cancelledAt,
  }) {
    _deal = _deal.copyWith(
      availableSlots: availableSlots,
      purchasedAt: purchasedAt,
      cancelledAt: cancelledAt,
      paidCount: _paid.length,
      collectedCount: _collected.length,
    );
    return _deal;
  }
}
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/data/repositories/reservation_repository_test.dart && flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: the host can mark a deal paid, bought, collected or cancelled"
```

---

### Task 5: The ViewModel knows what the host can do

**Files:**
- Modify: `lib/ui/split_board/deal_details_viewmodel.dart`
- Test: `test/ui/split_board/deal_details_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/ui/split_board/deal_details_viewmodel_test.dart`:

```dart
  test('the host is told what is still to collect', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.reserveSlotFor('bea');
    await repository.reserveSlotFor('cy');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    // Only the host's own slot is paid, and that is not money they hold.
    expect(viewModel.paymentLabel, '1 of 4 paid — P300 still to collect');

    await viewModel.setPaid('ana', paid: true);
    expect(viewModel.paymentLabel, '2 of 4 paid — P200 still to collect');
  });

  test('the host can buy once the deal is full, and not before', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'host',
    );
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    expect(viewModel.canMarkPurchased, isFalse);

    await repository.reserveSlotFor('ana');
    viewModel.refreshDeal(repository.deal);
    expect(viewModel.canMarkPurchased, isTrue);

    await viewModel.markPurchased();
    expect(viewModel.deal.status, DealStatus.readyForPickup);
    expect(viewModel.canMarkPurchased, isFalse);
    expect(viewModel.canMarkCollected, isTrue);
  });

  test('a student sees no host controls', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'ana',
    );
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'ana',
    );
    await pumpEventQueue();

    expect(viewModel.isHost, isFalse);
    expect(viewModel.canMarkPurchased, isFalse);
    expect(viewModel.canCancelDeal, isFalse);
    expect(viewModel.canMarkPaid, isFalse);
  });

  test('cancelling names the money the host is holding', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.reserveSlotFor('bea');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    await viewModel.setPaid('ana', paid: true);
    await viewModel.setPaid('bea', paid: true);

    expect(viewModel.canCancelDeal, isTrue);
    expect(viewModel.refundWarning, '2 students have paid you P200.');

    await viewModel.cancelDeal();
    expect(viewModel.deal.status, DealStatus.cancelled);
    expect(viewModel.canCancelDeal, isFalse);
    expect(viewModel.canReserve, isFalse);
  });

  test('nobody has paid, so there is nothing to warn about', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    expect(viewModel.refundWarning, isNull);
  });

  test('a paid student cannot cancel their slot', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    await repository.reserveSlotFor('ana');
    await repository.setPaidAsHost('ana');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'ana',
    );
    await pumpEventQueue();

    expect(viewModel.holdsSlot, isTrue);
    expect(viewModel.canCancel, isFalse);
  });
```

`hostedDeal` is a local helper in that test file:

```dart
Deal hostedDeal({required int availableSlots, required int totalSlots}) {
  return Deal(
    id: 'd',
    hubId: 'h',
    createdBy: 'host',
    title: 'Rice',
    category: DealCategory.grocery,
    totalPrice: 400,
    amount: 20,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: totalSlots,
    pickupLocation: 'Lobby',
    paidCount: 1,
  );
}
```

`setPaidAsHost` is the mock seam added in Task 4 — `setPaid` refuses a non-host
caller, and this test's mock is acting as Ana.

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/ui/split_board/deal_details_viewmodel_test.dart`
Expected: compile errors — `paymentLabel`, `canMarkPurchased`, `canCancelDeal`,
`canMarkPaid`, `canMarkCollected`, `refundWarning`, `setPaid`, `markPurchased`,
`cancelDeal`, `refreshDeal` are not defined.

- [ ] **Step 3: Extend the ViewModel**

In `lib/ui/split_board/deal_details_viewmodel.dart`, add the getters beside the
existing `canReserve` / `canCancel`, and tighten those two:

```dart
  bool get isCancelled => _deal.status == DealStatus.cancelled;
  bool get isCompleted => _deal.status == DealStatus.completed;
  bool get isPurchased => _deal.purchasedAt != null;

  /// Once the host has bought or called it off, the count they spent money
  /// against is final: nobody joins and nobody leaves.
  bool get isClosed => isPurchased || isCancelled;

  bool get currentUserHasPaid => _participants.any(
    (participant) => participant.userId == currentUserId && participant.hasPaid,
  );

  /// The host is the person everyone else is relying on, so they cannot walk
  /// away from their own buy; past the deadline the host is about to spend real
  /// money against a count that must now be final; and a student who has paid
  /// would be leaving the host holding money they owe back.
  bool get canCancel =>
      holdsSlot &&
      !isHost &&
      !deadlinePassed &&
      !isClosed &&
      !currentUserHasPaid;

  bool get canReserve => !holdsSlot && !isFull && !deadlinePassed && !isClosed;

  /// The host's levers. The screen offers "I've bought it" from Full onward —
  /// the normal path — though the database does not insist on it.
  bool get canMarkPurchased => isHost && isFull && !isPurchased && !isCancelled;
  bool get canCancelDeal => isHost && !isCompleted && !isCancelled;
  bool get canMarkPaid => isHost && !isCancelled;
  bool get canMarkCollected => isHost && isPurchased && !isCancelled;

  /// What the host is still owed. The host's own slot counts as paid — they
  /// cannot pay themselves — so it is in the tally but not in the money.
  String get paymentLabel {
    final total = _deal.participantCount;
    final paid = _deal.paidCount;
    if (paid >= total) return 'Everyone has paid.';
    final owed = (total - paid) * _deal.pricePerShare;
    return '$paid of $total paid — ${formatPeso(owed)} still to collect';
  }

  /// Named in the cancel dialog before the host is allowed to go through with
  /// it. Null when there is nothing to hand back.
  String? get refundWarning {
    final students = _deal.studentsWhoPaid;
    if (students == 0) return null;
    final plural = students == 1 ? 'student has' : 'students have';
    return '$students $plural paid you ${formatPeso(_deal.amountHeld)}.';
  }

  Future<void> setPaid(String userId, {required bool paid}) => _mutate(
    () => _reservationRepository.setPaid(_deal.id, userId, paid: paid),
  );

  Future<void> setCollected(String userId, {required bool collected}) =>
      _mutate(
        () => _reservationRepository.setCollected(
          _deal.id,
          userId,
          collected: collected,
        ),
      );

  Future<void> markPurchased() =>
      _mutate(() => _reservationRepository.markPurchased(_deal.id));

  Future<void> cancelDeal() =>
      _mutate(() => _reservationRepository.cancelDeal(_deal.id));

  /// Test seam: adopt a deal changed outside this ViewModel.
  void refreshDeal(Deal deal) {
    _deal = deal;
    notifyListeners();
  }
```

`_mutate` already refetches participants after every action, so the paid and
collected ticks on screen refresh themselves.

Import `formatPeso` — it is a top-level function in `models/deal.dart`, which is
already imported.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/ui/split_board/deal_details_viewmodel_test.dart && flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: the details view model drives the host's four levers"
```

---

### Task 6: The details screen shows the lifecycle

**Files:**
- Modify: `lib/ui/split_board/deal_details_screen.dart`
- Test: `test/ui/split_board/deal_details_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/ui/split_board/deal_details_screen_test.dart`:

```dart
  testWidgets('the host sees who has paid, and what is left to collect', (
    tester,
  ) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    expect(find.text('1 of 2 paid — P100 still to collect'), findsOneWidget);
    expect(find.byKey(const Key('mark-paid-ana')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mark-paid-ana')));
    await tester.pumpAndSettle();

    expect(find.text('Everyone has paid.'), findsOneWidget);
  });

  testWidgets('a student sees the state but cannot change it', (tester) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    await repository.reserveSlotFor('ana');

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'ana',
    );

    expect(find.byKey(const Key('mark-paid-ana')), findsNothing);
    expect(find.byKey(const Key('detail-mark-purchased-button')), findsNothing);
    expect(find.byKey(const Key('detail-cancel-deal-button')), findsNothing);
  });

  testWidgets('cancelling warns the host what they owe back', (tester) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.setPaidAsHost('ana');

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    final cancelButton = find.byKey(const Key('detail-cancel-deal-button'));
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(find.text('1 student has paid you P100.'), findsOneWidget);
    expect(
      find.text(
        'Cancelling does not refund them — you will have to hand it back '
        'yourself.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel the deal'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('the host can back out of cancelling', (tester) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    final cancelButton = find.byKey(const Key('detail-cancel-deal-button'));
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep the deal'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
```

The file already has `pumpDetails(tester, deal, {currentUserId})`, but it builds
its own `MockReservationRepository` internally, so a test cannot seed the deal
with students and payments first. Add a second helper beside it that takes the
repository already prepared, and keep the existing one untouched:

```dart
  Future<void> pumpDetailsWith(
    WidgetTester tester, {
    required MockReservationRepository repository,
    required String currentUserId,
  }) async {
    // Tall enough that the whole scrollable body renders onstage, so plain
    // find.text / find.byKey see it without a manual scroll.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => DealDetailsViewModel(
            deal: repository.deal,
            currentUserId: currentUserId,
            reservationRepository: repository,
          ),
          child: const DealDetailsScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Deal hostedDeal({required int availableSlots, required int totalSlots}) {
    return Deal(
      id: 'd',
      hubId: 'h',
      createdBy: 'host',
      hostName: 'Marco Villanueva',
      title: 'Rice',
      category: DealCategory.grocery,
      totalPrice: 400,
      amount: 20,
      unit: DealUnit.kg,
      availableSlots: availableSlots,
      totalSlots: totalSlots,
      pickupLocation: 'Lobby',
      paidCount: 1,
    );
  }
```

The tests above call `pumpDetails(tester, repository: ..., currentUserId: ...)` —
rename those calls to `pumpDetailsWith`.

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/ui/split_board/deal_details_screen_test.dart`
Expected: FAIL — none of the new keys or text are on screen.

- [ ] **Step 3: Show paid and collected per participant**

In `lib/ui/split_board/deal_details_screen.dart`, `_Participants` needs the
ViewModel to render the host's buttons. Change its constructor to take it:

```dart
class _Participants extends StatelessWidget {
  const _Participants({super.key, required this.viewModel});

  final DealDetailsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participants = viewModel.participants;

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
            padding: const EdgeInsets.only(bottom: 10),
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
                Expanded(
                  child: Text(
                    participant.isHost
                        ? '${participant.displayName} (organiser)'
                        : participant.displayName,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                _PaidControl(viewModel: viewModel, participant: participant),
                if (viewModel.isPurchased) ...[
                  const SizedBox(width: 8),
                  _CollectedControl(
                    viewModel: viewModel,
                    participant: participant,
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          viewModel.paymentLabel,
          key: const Key('detail-payment-label'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The host taps to mark a payment; everyone else just reads it.
class _PaidControl extends StatelessWidget {
  const _PaidControl({required this.viewModel, required this.participant});

  final DealDetailsViewModel viewModel;
  final Reservation participant;

  @override
  Widget build(BuildContext context) {
    // The host's own slot is paid from the moment the deal exists, and they
    // cannot unpay themselves.
    if (!viewModel.canMarkPaid || participant.isHost) {
      return _StateChip(
        label: participant.hasPaid ? 'Paid' : 'Unpaid',
        on: participant.hasPaid,
      );
    }

    return TextButton(
      key: Key('mark-paid-${participant.userId}'),
      onPressed: viewModel.isUpdating
          ? null
          : () => viewModel.setPaid(
              participant.userId,
              paid: !participant.hasPaid,
            ),
      child: _StateChip(
        label: participant.hasPaid ? 'Paid' : 'Mark paid',
        on: participant.hasPaid,
      ),
    );
  }
}

class _CollectedControl extends StatelessWidget {
  const _CollectedControl({
    required this.viewModel,
    required this.participant,
  });

  final DealDetailsViewModel viewModel;
  final Reservation participant;

  @override
  Widget build(BuildContext context) {
    if (!viewModel.canMarkCollected || participant.isHost) {
      return _StateChip(
        label: participant.hasCollected ? 'Collected' : 'Not collected',
        on: participant.hasCollected,
      );
    }

    return TextButton(
      key: Key('mark-collected-${participant.userId}'),
      onPressed: viewModel.isUpdating
          ? null
          : () => viewModel.setCollected(
              participant.userId,
              collected: !participant.hasCollected,
            ),
      child: _StateChip(
        label: participant.hasCollected ? 'Collected' : 'Mark collected',
        on: participant.hasCollected,
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: on
            ? const Color(0xFFDCEFE3)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: on
              ? const Color(0xFF7FB99A)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: on
              ? const Color(0xFF173E28)
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
```

Update its call site: `_Participants(key: const Key('detail-participants'), viewModel: viewModel)`.

- [ ] **Step 4: Give the host their two buttons**

Replace the `if (viewModel.isHost) ... else FilledButton(...)` block near the
bottom of the screen with:

```dart
                  if (viewModel.isHost) ...[
                    Container(
                      key: const Key('detail-host-slot-note'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        'You are organising this buy, so one slot is yours.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (viewModel.canMarkPurchased) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('detail-mark-purchased-button'),
                        onPressed: viewModel.isUpdating
                            ? null
                            : viewModel.markPurchased,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text("I've bought it"),
                      ),
                    ],
                    if (viewModel.canCancelDeal) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('detail-cancel-deal-button'),
                        onPressed: viewModel.isUpdating
                            ? null
                            : () => _confirmCancel(context, viewModel),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Cancel this deal'),
                      ),
                    ],
                  ] else
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

- [ ] **Step 5: The cancel dialog names the money**

Add to the screen's `State` (or as a top-level function in the file):

```dart
  /// The app never moves money. What it refuses to do is let the host cancel
  /// while pretending nobody paid.
  Future<void> _confirmCancel(
    BuildContext context,
    DealDetailsViewModel viewModel,
  ) async {
    final warning = viewModel.refundWarning;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this deal?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning != null) ...[
              Text(
                warning,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cancelling does not refund them — you will have to hand it '
                'back yourself.',
              ),
            ] else
              const Text(
                'Nobody has paid you yet, so there is nothing to hand back. '
                'The deal will close and its slots will be released.',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep the deal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel the deal'),
          ),
        ],
      ),
    );

    if (confirmed == true) await viewModel.cancelDeal();
  }
```

`DealDetailsScreen` is currently a `StatelessWidget`; `_confirmCancel` is a
method on it, so no conversion is needed. It must not use a `BuildContext` across
an `await` — the `await viewModel.cancelDeal()` happens after the dialog closes
and touches no context, which is safe and what the analyzer checks.

- [ ] **Step 6: Run the tests**

Run: `flutter test test/ui/split_board/deal_details_screen_test.dart && flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: the details screen tracks payment, pickup and cancellation"
```

---

### Task 7: The board tells the truth

**Files:**
- Modify: `lib/ui/split_board/split_board_screen.dart`
- Test: `test/ui/split_board/deal_card_test.dart`
- Test: `test/ui/split_board/split_board_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

In `test/ui/split_board/deal_card_test.dart`:

```dart
  testWidgets('a full deal says Full, not Open', (tester) async {
    await pumpCard(
      tester,
      deal: dealWith(totalSlots: 4, availableSlots: 0, paidCount: 1),
    );

    expect(find.text('Full'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('a nearly full deal says Filling fast', (tester) async {
    await pumpCard(
      tester,
      deal: dealWith(totalSlots: 8, availableSlots: 2, paidCount: 1),
    );

    expect(find.text('Filling fast'), findsOneWidget);
  });

  testWidgets('a bought deal says Ready for pickup', (tester) async {
    await pumpCard(
      tester,
      deal: dealWith(
        totalSlots: 4,
        availableSlots: 0,
        paidCount: 4,
        purchasedAt: DateTime(2026, 7, 16),
      ),
    );

    expect(find.text('Ready for pickup'), findsOneWidget);
  });
```

In `test/ui/split_board/split_board_viewmodel_test.dart`:

```dart
  test('finished deals are off the board unless asked for', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _StubDealRepository([
        dealWith(id: 'open', totalSlots: 4, availableSlots: 2),
        dealWith(
          id: 'done',
          totalSlots: 4,
          availableSlots: 0,
          paidCount: 4,
          collectedCount: 4,
          purchasedAt: DateTime(2026, 7, 16),
        ),
        dealWith(
          id: 'dead',
          totalSlots: 4,
          availableSlots: 2,
          cancelledAt: DateTime(2026, 7, 16),
        ),
      ]),
      hubId: 'h',
      hubName: 'Hub',
    );
    await pumpEventQueue();

    expect(viewModel.filteredDeals.map((d) => d.id), ['open']);

    viewModel.updateStatusFilter(DealStatus.cancelled);
    expect(viewModel.filteredDeals.map((d) => d.id), ['dead']);
  });
```

`_FakeDealRepository` already exists in `split_board_viewmodel_test.dart` — use
it. `dealWith` is a local helper in each of the two test files, and it is the
same shape as `deal()` in `deal_status_test.dart` with an added `id`:

```dart
Deal dealWith({
  String id = 'd',
  required int totalSlots,
  required int availableSlots,
  int paidCount = 0,
  int collectedCount = 0,
  DateTime? purchasedAt,
  DateTime? cancelledAt,
}) {
  return Deal(
    id: id,
    hubId: 'h',
    title: 'Rice',
    category: DealCategory.grocery,
    totalPrice: 400,
    amount: 20,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: totalSlots,
    pickupLocation: 'Lobby',
    paidCount: paidCount,
    collectedCount: collectedCount,
    purchasedAt: purchasedAt,
    cancelledAt: cancelledAt,
  );
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/ui/split_board/deal_card_test.dart test/ui/split_board/split_board_viewmodel_test.dart`
Expected: FAIL — the card still prints the old labels; the board still shows all
three deals.

(The card and the ViewModel were changed in Task 1, so some of these may already
pass. Any that do are proof Task 1 landed, not a reason to skip writing them.)

- [ ] **Step 3: Check the filter, and change nothing**

`lib/ui/split_board/split_board_screen.dart:227` already builds its dropdown with
`for (final status in DealStatus.values)`, so the six appear on their own and
`filling_fast` disappears on its own. **No edit is needed here.** This step exists
so the implementer confirms it rather than assuming it.

- [ ] **Step 4: Run the tests**

Run: `flutter test && flutter analyze`
Expected: all pass, no issues.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: the board badge stops lying about a deal's status"
```

---

### Task 8: Prove it against the live project, then on the emulator

**Files:** none — this is verification.

- [ ] **Step 1: Ask the user to apply the migration**

Send them `supabase/migrations/20260716000000_add_deal_lifecycle.sql` to paste
into the Supabase SQL editor. Paste it in chunks if the editor complains — it has
mangled long scripts before.

- [ ] **Step 2: Prove the refusals in SQL**

Ask the user to run this and send the result. It impersonates a non-host and
checks that every host-only function refuses, that the goods cannot be collected
before they are bought, and that a paid student cannot walk away.

```sql
-- Two students in one deal: the host, and someone who is not.
create temporary table t_result (check_name text, passed boolean, detail text);

do $test$
declare
  v_deal_id uuid;
  v_host uuid;
  v_other uuid;
begin
  select id, created_by into v_deal_id, v_host
  from public.deals
  order by created_at desc
  limit 1;

  select user_id into v_other
  from public.deal_reservations
  where deal_id = v_deal_id and user_id <> v_host
  limit 1;

  -- Impersonate a student who is not the host.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_other)::text, true);

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
    insert into t_result values ('non-host cannot mark paid', false, 'it allowed it');
  exception when sqlstate 'P0012' then
    insert into t_result values ('non-host cannot mark paid', true, 'P0012');
  end;

  -- Now as the host.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host)::text, true);

  begin
    perform public.set_participant_collected(v_deal_id, v_other, true);
    insert into t_result values ('no collecting before buying', false, 'it allowed it');
  exception when sqlstate 'P0007' then
    insert into t_result values ('no collecting before buying', true, 'P0007');
  end;

  perform public.set_participant_paid(v_deal_id, v_other, true);

  -- A student who has paid cannot quietly leave.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_other)::text, true);

  begin
    perform public.cancel_reservation(v_deal_id);
    insert into t_result values ('a paid student cannot walk', false, 'it allowed it');
  exception when sqlstate 'P0011' then
    insert into t_result values ('a paid student cannot walk', true, 'P0011');
  end;

  -- Put it back.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host)::text, true);
  perform public.set_participant_paid(v_deal_id, v_other, false);
end;
$test$;

select * from t_result;
```

Expected: five rows, `passed` true on every one.

- [ ] **Step 3: Verify on the emulator**

Run the app (`flutter run -d emulator-5554`), sign in, open the Rice deal in
Magallanes, and check:

- The badge on a deal with slots left reads **Open**, and the one with a single
  slot left reads **Filling fast**.
- As the host, **Who is in** lists each student with a **Mark paid** button, and
  the line beneath reads *"1 of 2 paid — P128.58 still to collect"*.
- Tapping **Mark paid** flips the chip to **Paid** and updates that line.
- Once every slot is claimed and paid, the badge reads **Ready to purchase** and
  the **I've bought it** button appears.
- Tapping it flips the badge to **Ready for pickup**, and **Mark collected**
  buttons appear.
- Ticking the last student collected flips the badge to **Completed**, and the
  deal disappears from the board's default view.
- On a second deal, **Cancel this deal** warns *"1 student has paid you P…"* and,
  once confirmed, the badge reads **Cancelled** and the deal leaves the board.

- [ ] **Step 4: Report**

Report exactly what was seen, including anything that did not match. A screenshot
of the Completed badge and of the cancel dialog is worth more than a description.
