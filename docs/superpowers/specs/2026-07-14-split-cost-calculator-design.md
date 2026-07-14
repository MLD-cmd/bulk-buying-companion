# Split-Cost Calculator — Design

Date: 2026-07-14
Status: Approved, ready for implementation planning

## Problem

The app already divides a bulk buy's total price across its slots, but it does so
with a raw floating-point division (`Deal.pricePerShare => totalPrice / totalSlots`)
and rounds the result only at display time. When the price does not divide evenly,
the shares no longer add back up to the total.

A ₱900 buy split 7 ways shows **₱128.57/share**. Seven students paying ₱128.57
hand over ₱899.99 — a centavo short of what the host paid. Nothing in the app
acknowledges the gap. This is the kind of discrepancy that causes an argument at
pickup, and it affects every deal already in the database whose price does not
divide cleanly.

Of the six subtasks on the Kanban card, five are already satisfied by existing
code (price input, participant count, cost-per-participant, summary display,
validation). **Handling uneven amounts is the only genuinely unbuilt one**, and it
is the substance of this work.

## Decisions

**Rounding policy: shares round up to the centavo; the host keeps the surplus.**
Every student pays an identical, quotable amount, and the host is never left
covering a shortfall. The overshoot is a few centavos and is stated openly rather
than hidden.

Rejected alternatives: rounding down (host silently absorbs the shortfall);
uneven shares where designated payers cover the remainder (every student pays a
different number); and rejecting inputs that do not divide evenly (pushes an
arithmetic problem onto the user).

**Scope: no new screen.** The "calculator" is the live preview that already
exists in the create-deal form. We fix the shared math so that preview, the deal
card, and the deal details screen all show a correct and reconcilable split. A
standalone calculator screen would add a second place to display the same number
without fixing the defect; it can be built later on top of correct logic if it is
ever wanted.

**Representation: integer centavos.** All splitting arithmetic is done in whole
centavos. Floating point never participates in the division. The alternative —
keeping doubles and ceiling to two decimals — reintroduces the same class of bug
we are fixing: a division can land a hair either side of an exact centavo and the
ceiling amplifies it into a wrong share. It would be right most of the time and
wrong occasionally, which is the worst failure mode for money. A decimal library
would be correct but is a new dependency for a two-field arithmetic problem.

## Architecture

### `CostSplit` — `lib/models/cost_split.dart`

A pure value type. No dependencies, no I/O, trivially testable.

```dart
class CostSplit {
  factory CostSplit.from({required double totalPrice, required int slots});

  final int totalCentavos;
  final int slots;

  int get perShareCentavos;    // ceil division: (total + slots - 1) ~/ slots
  int get collectedCentavos;   // perShareCentavos * slots
  int get surplusCentavos;     // collected - total; >= 0 by construction
  bool get isEven;             // surplus == 0

  double get pricePerShare;    // perShareCentavos / 100 — display only
}
```

Ceiling division is performed on integers, so the shares provably sum to
`collectedCentavos` and the surplus is provably non-negative. There is no
rounding step that can drift.

`pricePerShare` exists solely so existing display code (`formatPeso`) keeps
working; it is derived from the integer, never used to compute one.

### Integration points

The codebase currently performs the same division in three places. After this
change there is one, and the rest delegate to it.

| Location | Change |
|---|---|
| `Deal.pricePerShare` (`lib/models/deal.dart`) | Delegates to `CostSplit`. Fixes the number everywhere it is already displayed — deal card and details screen both read this getter. |
| `CreateDealViewModel.previewPricePerShare` | Delegates to `CostSplit` instead of dividing itself, so the poster's preview matches what students later see. |
| `SplitBoardViewModel._priceValue` (line ~150) | Drops the regex. It currently sorts by regex-parsing the *formatted display string* (`"P128.58/share"`) back into a number — a number → text → number round-trip that breaks if the label format changes. Sorts on the real numeric per-share instead. |

### Calculation summary

On an even split, the UI is unchanged.

On an uneven split, the create-deal preview and the deal details screen each gain
a quiet, factual line noting that the shares collect slightly more than the item
costs and that the difference stays with the host. This converts a silent
discrepancy into a stated one, which is the point of the "handle uneven amounts"
subtask.

## Validation

`validateTotalPrice` currently requires only `> 0`, so ₱0.001 passes and rounds
to zero centavos — a deal where every participant pays nothing. Add a floor of
**₱0.01** on the total price. This also guarantees `totalCentavos >= 1`, keeping
`CostSplit` total over its input domain.

Slot bounds (`kMinDealSlots` = 2, `kMaxDealSlots` = 50) are already enforced and
do not change. `CostSplit` still guards `slots >= 1` internally rather than
trusting its callers.

## Testing

`CostSplit` is pure arithmetic and tests cheaply:

- **Even split** — ₱900 ÷ 5 = ₱180.00/share, zero surplus.
- **Uneven split** — ₱900 ÷ 7 = ₱128.58/share; 7 shares collect ₱900.06;
  surplus ₱0.06.
- **Invariant, across a range of inputs** — shares × per-share is always ≥ the
  total, and the gap is always strictly less than one centavo per slot. This is
  the real property being guaranteed and is worth asserting broadly rather than
  on a couple of hand-picked cases.
- **Bounds** — the 2-slot floor and the 50-slot ceiling.
- **Minimum price** — ₱0.01 is accepted and produces a non-zero share; anything
  below it is rejected by validation.

Existing widget tests that assert the old, incorrect figure are updated.

## Known consequence

This visibly changes the per-share number shown for existing deals that do not
divide evenly (₱128.57 → ₱128.58). That is the bug being fixed, not a
regression — but numbers already on screen will move.

## Out of scope

A **wallet** was discussed and deliberately deferred. It decomposes into two
separate pieces, neither of which belongs in this card:

- A **"what I owe" ledger** — a read-only view over deals you have joined, using
  the per-share figure this work makes correct. No money moves. A reasonable next
  card, and a natural sequel to this one.
- A **real balance** that students load funds into and pay from. This is not a
  feature but a subsystem: holding user funds makes the app a money transmitter
  (BSP-regulated e-money territory in the Philippines), and demands an immutable
  double-entry ledger, idempotent transactions, provider reconciliation, and
  dispute and chargeback handling. If a payment experience is wanted, the app
  should **record settlement** (host marks a share as paid; students settle in
  cash or via GCash directly) or **hand off** to a payment provider so funds never
  rest in the app.

Both require their own design. Neither is blocked by this work; both benefit from
it landing first.
