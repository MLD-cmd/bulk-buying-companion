# Slot Reservation System — Design

Date: 2026-07-14
Status: Approved, ready for implementation planning

## Problem

A deal's "Reserve a slot" button does nothing. It shows a snackbar saying the
feature is coming, and `deal_details_screen.dart` names this card in a comment.
`available_slots` is written once when a deal is published and never changes, so
no deal can ever fill, and nothing records who is actually in a buy.

This blocks the **Automatic Deal Status** card entirely: every one of its
subtasks ("change to Full when slots are filled") waits on a slot count that
only reservations can move.

## Decisions

**One slot per student per deal.** A 7-slot deal means 7 different students.
"Prevent duplicate reservations" becomes a database constraint —
`primary key (deal_id, user_id)` — rather than application logic that has to be
remembered on every code path. Reserve becomes a toggle: Reserve ↔ Cancel.

A student wanting a larger portion is not served by claiming two of seven
shares; they are served by the poster choosing a slot count that makes each
share the right size. Slot count *is* portion size. If multi-slot holding is
ever wanted, it is additive: a `slots int not null default 1` column and a
relaxed constraint, with existing rows still valid.

**The host holds a slot automatically.** "25kg Rice Sack — Split 5 ways" means
*me and four others*; nobody writes that meaning "I will buy rice for five other
people and take none." Publishing a deal therefore creates the host's
reservation and posts the deal with `total_slots - 1` open.

The host's slot **cannot be cancelled**. This is correct rather than a
limitation: the host fronts the money and buys the goods, and everyone else is
relying on them. A host who wants out should cancel the *deal*, not their slot.

**Cancellation is allowed until `closes_at`.** This gives the existing, currently
decorative deadline field a real meaning, is predictable for students ("you can
back out until Thursday"), and protects the host at the moment they are about to
spend real money. A deal with **no deadline stays cancellable indefinitely** —
the honest consequence of not setting one.

**Slot claiming is atomic, in Postgres.** See below.

## The concurrency problem

Two students tap Reserve on the last slot at the same instant. The deal must not
sell 8 shares of a 7-slot buy — someone would pay for goods that do not exist.

**Rejected: doing it in the Flutter client.** Read `available_slots`, check it is
above zero, insert a reservation, write back the decrement. Both students' apps
read "1 slot left" before either writes; both pass the check; both insert; the
deal oversells. No amount of care in Dart fixes this, because the check and the
write are separate round-trips with a gap between them. Named here explicitly so
it is not rediscovered later.

**Rejected: deriving the count and dropping the stored column.** Compute
`available_slots` in a view as `total_slots - count(reservations)`, the way
`hub_directory` already derives `member_count` from `hub_memberships`. This is
architecturally purer — one source of truth, which cannot drift — and it was
tempting for exactly that reason. But it still needs a lock: two concurrent
inserts would each count "6 of 7 taken" and both proceed, yielding 8
reservations, and the unique constraint cannot help because they are different
users. That means a trigger that locks the deal row before counting, *plus* a
derived view — more moving parts than the chosen approach, harder to test, and
harder to debug. The lock must exist either way; the chosen approach puts it
somewhere visible.

**Chosen: Postgres RPCs.** A `reserve_slot` function runs entirely inside one
transaction: it inserts the reservation row and decrements `available_slots`
with a conditional update (`... where available_slots > 0`). Postgres serialises
concurrent callers on that row. The loser updates zero rows, the transaction
aborts, and they are told the deal just filled — which is the truth. The client
becomes dumb: call the function, react to what the database says.

**Guarding the stored counter.** A denormalised counter can drift from the truth
it summarises — that is exactly the bug fixed in the hub member count earlier
today. It is closed off here by making the RPC the *only* thing permitted to
write `available_slots`: direct update rights on the column are revoked, so no
client, present or future, can set it by hand. Combined with the existing
`CHECK (available_slots >= 0)` and `CHECK (available_slots <= total_slots)`
constraints, the database structurally cannot represent an oversold deal.

## Schema

### `deal_reservations`

| Column | Notes |
|---|---|
| `deal_id` | FK → `deals(id)` on delete cascade |
| `user_id` | FK → `auth.users(id)` on delete cascade |
| `reserved_at` | `timestamptz not null default now()` |

`primary key (deal_id, user_id)` — this *is* "prevent duplicate reservations".

RLS: a student may read reservations for deals in their own hub, and may insert
or delete only their own row. All slot mutation in practice goes through the
RPCs, which are `security definer`.

### RPCs

- **`reserve_slot(p_deal_id)`** — inserts the caller's reservation and
  decrements `available_slots where available_slots > 0`. Raises if the deal is
  full or the caller already holds a slot. Returns the updated deal row.
- **`cancel_reservation(p_deal_id)`** — deletes the caller's reservation and
  increments `available_slots`. Refuses if `closes_at` has passed, and refuses
  for the deal's host. Returns the updated deal row.

Both return the updated deal so the client never has to guess the new count.

### Host slot via trigger

On insert into `deals`: a `BEFORE` trigger sets
`available_slots := total_slots - 1`, and an `AFTER` trigger writes the host's
reservation row. Both run inside the insert's own transaction, so **no deal can
exist without its host's reservation, on any code path.**

Doing this in the Dart repository instead would leave a window in which a deal
exists whose numbers lie, and would mean rewriting `createDeal`. The trigger owns
the invariant; `SupabaseDealRepository` simply stops sending `available_slots`,
and `MockDealRepository` mirrors the rule so mock and production agree.

### `deal_participants` view

Exposes who holds a slot, joining `profiles` for display names — the same device
`deal_feed` already uses for `host_name`, and for the same reason: `profiles` is
own-row-only RLS, so a name must come through a view.

## Dart architecture

Follows the existing layering exactly; no new patterns are introduced.

| File | Responsibility |
|---|---|
| `lib/models/reservation.dart` | **New.** `Reservation`: `dealId`, `userId`, `studentName`, `reservedAt`, `isHost`. |
| `lib/data/repositories/reservation_repository.dart` | **New.** Abstract `ReservationRepository` + `MockReservationRepository` + `SupabaseReservationRepository` wrapping a `SupabaseReservationGateway`, matching the shape of `DealRepository`/`HubRepository`. A `ReservationFailure` carries the user-facing message. A new file rather than growing `deal_repository.dart`, which is already 271 lines. |
| `lib/ui/split_board/deal_details_viewmodel.dart` | **New.** Holds the deal, the participant list, `isReserving`, and any failure message. Exposes `reserve()` and `cancel()`. |
| `lib/ui/split_board/deal_details_screen.dart` | Gains a `ChangeNotifierProvider` in `route()` (mirroring `CreateDealScreen.route`) and a `Consumer` in `build`. Adds the participant list. |
| `lib/ui/split_board/split_board_screen.dart` | Consumes the updated deal popped from the details route. |

`DealDetailsScreen` is a `StatelessWidget` with no ViewModel today — the one
place the codebase departs from MVVM. This card is what forces it into line.

`DealDetailsViewModel.reserve()`/`cancel()` get the same re-entrancy guard added
to `JoinHubViewModel.join()` earlier today, and for the same reason: a
double-tapped Reserve must not fire twice. The button also disables while a call
is in flight, so the guard is a backstop rather than the only defence.

## Error handling

`SupabaseReservationRepository` maps Postgres errors to user-facing messages, as
`SupabaseDealRepository` already does:

| Cause | Message |
|---|---|
| Deal filled during the call | "This deal just filled up." |
| Already holds a slot (`23505`) | "You already have a slot in this deal." |
| Cancelling after `closes_at` | "The deadline has passed — you can no longer cancel." |
| Host cancelling own slot | "You are organising this buy, so your slot cannot be cancelled." |
| Anything else | "Could not reserve the slot. Please try again." |

## The board stays honest

`DealDetailsScreen.route` becomes `Route<Deal>` and pops the updated deal so
`SplitBoardScreen` can replace it in its list — the pattern the create-deal flow
already uses. Without this, a student would reserve a slot, hit back, and see the
old count on the card.

## Testing

The RPCs are where correctness lives, so the concurrency claim is tested
directly: **two overlapping `reserve_slot` calls on a one-slot deal — exactly one
wins, `available_slots` lands at 0, and two reservation rows never exist.**

Then the ordinary cases: reserve; cancel; duplicate rejected; full rejected;
cancel-after-deadline rejected; cancel with no deadline allowed; the host's slot
present at publish and not cancellable; the participant list renders.

`MockReservationRepository` mirrors the real rules — including rejecting
duplicates and refusing the host's cancellation — so ViewModel tests are honest
rather than passing against a permissive fake.

## Known gap, owned elsewhere

Under this design **a host has no way out**: their slot cannot be cancelled, and
there is no way to cancel a deal at all. That gap is real. It belongs to the
**Automatic Deal Status** card, which already carries an "Add 'Cancelled' status"
subtask. It is not smuggled in here, but the host is committed until that card
lands.

## Out of scope

- **Deal cancellation** and status transitions (Full, Ready to Purchase, Ready
  for Pickup, Completed, Cancelled) — the Automatic Deal Status card, which this
  work unblocks.
- **Physical share breakdown** — telling a student they receive 3.57 kg or 6
  bottles rather than "one slot". Its own card. A slot is currently a payment
  share, not a defined portion of goods; that card gives it a physical meaning,
  and must distinguish continuous goods (rice divides freely) from discrete ones
  (30 eggs across 4 slots is 7.5 eggs each, which nobody can collect).
- **Multiple slots per student** — additive later, as described above.
