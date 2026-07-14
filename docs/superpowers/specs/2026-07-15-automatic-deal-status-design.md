# Automatic Deal Status — Design

Date: 2026-07-15
Status: Approved, ready for implementation planning

## Problem

A deal's status is a lie, and has been since the day it was added.

`deals.status` is `not null default 'open'`, constrained to `open`,
`filling_fast`, `full`. The repository writes `'open'` on insert. **Nothing ever
updates it.** The `reserve_slot` and `cancel_reservation` RPCs move
`available_slots` but never touch `status`, so a deal whose last slot was just
taken still shows a green **Open** badge. Every real row in the database says
`'open'`. `filling_fast` cannot occur at all — it exists only in the mock's
seeded demo data.

Underneath the broken badge is a missing feature. A bulk buy has a life: slots
fill, students pay the host, the host buys the goods, students collect their
share, and the deal is done — or the host calls it off. The app models none of
it. It cannot answer the two questions that decide whether a host dares spend
their own money:

- **Has everyone paid me?**
- **Who still hasn't collected their share?**

There is no payment tracking anywhere in the codebase. No `paid` column, no
wallet, nothing.

The reservation migration already anticipated this card, in a comment on
`cancel_reservation`:

> Everyone else is relying on the host. They cannot quietly slip out; to get out
> they must cancel the deal, **which is the Automatic Deal Status card**.

Cancelling a deal does not exist yet. The details screen promises it —
*"To pull out you would have to cancel the whole deal"* — and the app cannot
keep that promise.

## Decisions

### Status is derived, never stored

**Drop `deals.status`.** Store only the facts that cannot be derived, and
compute the status from them.

The column already proved why. It did not drift over months; it was wrong on the
first day, because a stored status has to be recomputed on every path that could
change it. This card adds five such paths (pay, unpay, purchase, collect, cancel)
on top of the two that already exist (reserve, cancel reservation). Seven chances
to forget. Derived, there is nothing to forget: a student cancelling their slot
on a Ready-to-Purchase deal drops it back to Open by itself, with no code path
written to make that happen.

It is also the pattern the codebase already uses. `CostSplit` does not store the
per-share price and `PhysicalShare` does not store the per-share weight; both
compute from the facts. Status is the same kind of thing — a reading of the
facts, not a fact itself.

**The facts that are stored:**

| Fact | Column | Who writes it |
|---|---|---|
| slots left | `deals.available_slots` (exists) | reserve / cancel RPCs |
| this student paid | `deal_reservations.paid_at` (new) | host |
| the host bought the goods | `deals.purchased_at` (new) | host |
| this student collected | `deal_reservations.collected_at` (new) | host |
| the host called it off | `deals.cancelled_at` (new) | host |

Timestamps rather than booleans: *when* a student paid is worth more than *that*
they paid, it costs the same to store, and a null is an unambiguous "not yet".

### The derivation

```
cancelled_at set                                 → Cancelled
purchased_at set, and everyone collected         → Completed
purchased_at set                                 → Ready for Pickup
no slots left, and everyone paid                 → Ready to Purchase
no slots left                                    → Full
otherwise                                        → Open
```

Purchase gates both Completed and Ready for Pickup, so goods that were never
bought cannot be reported as collected even if the data were corrupted.

**It lives in Dart, on `Deal`,** not in the SQL view. One implementation, unit
testable without a database, and the mock repository and the Supabase repository
cannot disagree about what "Full" means. The view's job is to expose the raw
facts.

The cost accepted: no `where status = 'open'` in SQL. The Split Board already
filters in Dart, so this costs nothing today. If SQL-side filtering is ever
needed it becomes a generated column — additive, not a rewrite.

### The ladder is a path, not a cage

A host may mark a deal purchased before every student has paid. Real hosts buy
early, and blocking them would make the app wrong rather than careful. The
derivation handles it without a special case: `purchased_at` set means Ready for
Pickup, whatever the paid count says. Ready to Purchase is the app telling the
host *it is now safe to spend*, not a gate they must pass through.

### "Filling fast" stops being a status

It becomes what it always really was: a label on an Open deal that is nearly
full. **An Open deal is filling fast when a quarter or less of its slots
remain** (`availableSlots * 4 <= totalSlots`). For a 7-slot deal that is the last
slot; for a 20-slot deal, the last five.

Not stored, not in the enum, nothing to keep in sync. It disappears from
`DealStatus` and from the database constraint.

### The host's own slot is paid at creation and collected at purchase

The host holds a slot from the moment the deal exists (an existing trigger). They
cannot pay themselves — they are the one collecting — so their `paid_at` is set
when that slot is created. If it were not, "everyone paid" could never become
true and Ready to Purchase would never fire.

Likewise, when the host marks the goods bought, they are physically holding them.
Their `collected_at` is set at the same moment. Otherwise the host would have to
tick themselves off a list to confirm they had handed themselves their own rice.

### Only the host may mark anything

Paid, collected, purchased and cancelled are all host-only, checked in Postgres
against `deals.created_by = auth.uid()`, not in Dart. A client-side permission
check is a suggestion, not a control — anything speaking to PostgREST can skip
it. That is the lesson from the `deal_feed` leak, and it applies with more force
here: a student who could mark themselves paid could push a deal to Ready to
Purchase and send the host out to spend money on a promise.

Only the host knows whether the money actually arrived. It is one-sided, and that
matches the reality of cash on campus: the host is the one holding the bag.

### Cancelling is allowed until the deal is Completed, and it never hides the money

The host can back out at Open, Full, Ready to Purchase, or Ready for Pickup. A
supplier runs out of stock; a host gets sick. Trapping them would leave deals
stuck forever with no way to close them.

But once anyone has paid, the app states plainly what is owed before it lets the
host cancel:

> **3 students have paid you P385.74.** Cancelling does not refund them — you
> will have to hand it back yourself.

**The app never moves money.** It records who paid; it does not transfer. What it
refuses to do is let the host cancel while pretending nobody paid.

Cancelled is terminal: no new reservations, no further marking, and the deal
drops off the Split Board's default view.

Rejected: **allowing cancellation after Completed.** The goods are bought, split
and collected; there is nothing left to cancel, and a "cancelled" completed deal
is a contradiction that every screen would then have to explain.

## Architecture

### `DealStatus` — `lib/models/deal.dart`

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
}
```

`fillingFast` is removed. It is no longer parsed from or written to the database,
so `_dealStatusFromValue` and `_statusValue` in the repository are deleted
outright.

### `Deal` — `lib/models/deal.dart`

Gains the stored facts and the derivation. `status` changes from a field to a
getter:

`participantCount` is **not** a new fact. Every claimed slot is a student in the
buy, and the reserve/cancel RPCs move `available_slots` and the reservation rows
in one transaction, so `totalSlots - availableSlots` *is* the participant count.
Storing it separately would be a second copy of a number that already exists —
exactly the drift this card is here to remove.

```dart
final DateTime? purchasedAt;
final DateTime? cancelledAt;
final int paidCount;
final int collectedCount;

int get participantCount => totalSlots - availableSlots;

DealStatus get status {
  if (cancelledAt != null) return DealStatus.cancelled;
  if (purchasedAt != null) {
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

bool get isFillingFast =>
    status == DealStatus.open && availableSlots * 4 <= totalSlots;

/// What the badge reads. "Filling fast" is a label on an Open deal, not a state.
String get statusLabel =>
    isFillingFast ? 'Filling fast' : status.label;

/// What the host is still owed. Drives the cancel warning and the paid counter.
int get unpaidCount => participantCount - paidCount;
double get amountCollected => paidCount * pricePerShare;
```

`participantCount > 0` guards both branches: a row claiming zero participants is
bad data, and `0 >= 0` would otherwise report it Completed.

The `Deal` returned straight from `createDeal` is built from the raw `deals` row,
which has no counts. It is a brand-new deal: one participant (the host), paid,
nothing collected. The repository supplies exactly that.

### `Reservation` — `lib/models/reservation.dart`

```dart
final DateTime? paidAt;
final DateTime? collectedAt;

bool get hasPaid => paidAt != null;
bool get hasCollected => collectedAt != null;
```

### Schema — `supabase/migrations/20260716000000_add_deal_lifecycle.sql`

```sql
alter table public.deals
  add column if not exists purchased_at timestamptz,
  add column if not exists cancelled_at timestamptz;

alter table public.deal_reservations
  add column if not exists paid_at timestamptz,
  add column if not exists collected_at timestamptz;
```

**The host's slot is paid.** The trigger that gives the host their reservation
sets it, and existing rows are backfilled:

```sql
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
```

**`deal_feed` exposes the facts and drops `status`.** It has to be DROP + CREATE,
not CREATE OR REPLACE — replacing a view cannot remove a column. The
hub-membership scoping added on 2026-07-14 stays: a view runs with its owner's
rights and ignores RLS on the tables underneath, so the view itself is the
security boundary.

```sql
drop view if exists public.deal_feed;

create view public.deal_feed as
select
  d.id, d.hub_id, d.created_by, d.title, d.description, d.category,
  d.total_price, d.amount, d.unit, d.total_slots, d.available_slots,
  d.pickup_location, d.closes_at, d.created_at,
  d.purchased_at, d.cancelled_at,
  p.display_name as host_name,
  c.participant_count,
  c.paid_count,
  c.collected_count
from public.deals d
left join public.profiles p on p.user_id = d.created_by
left join lateral (
  select
    count(*)                as participant_count,
    count(r.paid_at)        as paid_count,
    count(r.collected_at)   as collected_count
  from public.deal_reservations r
  where r.deal_id = d.id
) c on true
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id and m.user_id = (select auth.uid())
);

grant select on public.deal_feed to authenticated;

alter table public.deals drop column status;
```

Dropping the column drops `deals_status_check` with it. No information is lost:
every row holds the default.

**`deal_participants` exposes the two new timestamps**, so the details screen can
show who has paid and who has collected:

```sql
create or replace view public.deal_participants as
select
  r.deal_id, r.user_id, r.reserved_at, r.paid_at, r.collected_at,
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
```

### The RPCs

`update` on `deals` is revoked from `authenticated`, and `deal_reservations` has
no insert/update/delete policy at all. Every mutation is a security-definer
function. Four are added.

**Every RPC returns the `deal_feed` row as `jsonb`, not `public.deals`.** The raw
deals row has no paid or collected counts, so a Dart `Deal` built from it would
report `paidCount: 0` and the badge would drop back to *Full* the moment the host
marked someone paid. Returning the feed row means every mutation hands back a
deal the app can render — the same shape `getDeals` already returns, through the
same `dealFromRow`.

`jsonb` rather than `returns public.deal_feed`: a function whose return type is a
view's rowtype pins that view in place, and `deal_feed` has now been dropped and
recreated twice (removing a column requires it). `jsonb` keeps the view free to
change.

This changes the return type of the two existing RPCs, so they must be
`drop function`-ed and recreated — `create or replace` cannot change a return
type — and re-granted.

A shared helper keeps the shape in one place:

```sql
create or replace function public.deal_feed_row(p_deal_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $fn$
  select to_jsonb(f) from public.deal_feed f where f.id = p_deal_id;
$fn$;
```

**`set_participant_paid(p_deal_id uuid, p_user_id uuid, p_paid boolean)`**

| Refusal | errcode |
|---|---|
| not signed in | `28000` |
| deal not found | `P0002` |
| caller is not the host | `P0012` |
| deal is cancelled | `P0006` |
| that student holds no slot | `P0005` |

Host-only refusals raise `P0012`, not the canonical `42501`. `ReservationRepository`
already maps `42501` to *"You can only reserve slots in your own hub"*, and one
code cannot carry two meanings in one message table.

Sets `paid_at = now()` when `p_paid`, `null` when not. Unmarking is allowed — a
host who mis-taps must be able to take it back. Marking paid is allowed after
purchase (a student can settle up late); it cannot move the status backwards,
because `purchased_at` already decides the branch.

**`set_participant_collected(p_deal_id uuid, p_user_id uuid, p_collected boolean)`**

Same refusals, plus:

| Refusal | errcode |
|---|---|
| the goods have not been bought | `P0007` |

Nobody collects goods that do not exist yet.

**`mark_purchased(p_deal_id uuid)`**

| Refusal | errcode |
|---|---|
| not signed in | `28000` |
| deal not found | `P0002` |
| caller is not the host | `P0012` |
| deal is cancelled | `P0006` |
| already bought | `P0008` |

Sets `purchased_at = now()` and, in the same transaction, the host's own
`collected_at` — they are holding the goods.

It does **not** require the deal to be Full or fully paid. The screen offers the
button from Full onward, which is the normal path; the function does not enforce
it, because a host who bought early has bought early and the app's job is to
record that, not to argue.

**`cancel_deal(p_deal_id uuid)`**

| Refusal | errcode |
|---|---|
| not signed in | `28000` |
| deal not found | `P0002` |
| caller is not the host | `P0012` |
| already cancelled | `P0009` |
| deal is completed | `P0010` |

Sets `cancelled_at = now()`. Completed is computed inside the function, from the
same rule Dart uses: bought, and every participant collected.

**Two existing RPCs gain refusals:**

- `reserve_slot`: a purchased or cancelled deal is closed (`P0006`). The count
  the host spent money against must be final.
- `cancel_reservation`: a student who has paid cannot quietly walk (`P0011`) —
  cancelling would leave the host holding money they owe back, with no record of
  it. They talk to the host, who unmarks the payment first. A cancelled or
  purchased deal likewise refuses (`P0006`).

### Repositories

All four go on `ReservationRepository`, which already owns the per-student slot.

```dart
Future<Deal> setPaid(String dealId, String userId, {required bool paid});
Future<Deal> setCollected(String dealId, String userId, {required bool collected});
Future<Deal> markPurchased(String dealId);
Future<Deal> cancelDeal(String dealId);
```

`markPurchased` and `cancelDeal` are deal-level and would sit more naturally on
`DealRepository` — but they read and write the same state the mock holds for
`reserveSlot`: one deal, one set of holders, one set of payments. Split across
two repositories, `MockDealRepository` and `MockReservationRepository` would each
hold their own copy of the deal and disagree the moment either changed it. One
mock, one truth.

Each has a Mock and a Supabase implementation, and each Supabase one calls the
matching RPC through the existing gateway, mapping the errcodes above to
sentences a student can act on — the same shape as the reservation errors.

## Screens

**Deal details.** The badge already exists and now reads the derived status.
Below it:

- **WHO IS IN** grows two columns: paid and collected. Every student sees the
  state; only the host sees the buttons that change it.
- The host sees what is outstanding: *"3 of 4 paid — P128.58 still to collect."*
- The host's action button is the deal's next step, and only appears when that
  step is real: **"I've bought it"** once the deal is Full, **"Cancel deal"**
  until Completed.
- Cancelling opens a dialog that names the refund before it will proceed.
- A student sees their own row's state and nothing to tap. The reserve and cancel
  buttons already there gain the new refusals' messages.

**Deal card.** The badge reads `statusLabel`, so a nearly-full Open deal says
*Filling fast* and a full one says *Full* — which is the bug that started this
card.

**Split Board.** Cancelled and Completed deals are not open business, so the
default view hides them. The existing status filter can bring them back, and now
lists all six states.

## Testing

The derivation is pure and tests without a database:

- Each of the six statuses from its facts, including the ones that overlap:
  a cancelled deal that is also full is Cancelled; a purchased deal that is not
  fully collected is Ready for Pickup.
- The reversal that motivated deriving it: a Ready-to-Purchase deal loses a
  student and becomes Open again.
- Filling fast at the boundary: 7 slots with 1 free is filling fast, with 2 free
  is not; a full deal is never filling fast.
- `participantCount == 0` is not Completed.

Then the repositories' error mapping, the host-only controls, the paid counter,
and the cancel dialog naming the amount.

**The refusals are proven in SQL against the live project**, as the reservation
RPCs were: a non-host is refused `42501` on every one of the four functions, a
paid student cannot cancel their slot, a collect before purchase is refused, and
a completed deal cannot be cancelled.

## Out of scope

- **Moving money.** The app records who paid; it does not transfer anything. A
  payments integration is its own project, and every decision here holds without
  it.
- **Auto-expiry at the deadline.** `closes_at` already blocks late cancellation
  of a slot. Whether a deal that never fills should expire itself is a separate
  question about what happens to the students who did pay.
- **Notifying students when the status changes.** There is no notification system
  yet; adding one here would drag push, permissions and delivery into a card
  about state.
- **Editing a posted deal.** Still no edit flow, and it would collide with money
  already collected.
