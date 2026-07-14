# Physical Share Breakdown — Design

Date: 2026-07-15
Status: Approved, ready for implementation planning

## Problem

The app models money per slot but not goods per slot. A student is told they
pay ₱128.58; they are never told they receive 3.57 kg.

The `quantity` field is the cause, and it means two different things depending
on the deal:

| Deal | `quantity` | What it actually is |
|---|---|---|
| 25kg Rice Sack | 1 | one sack — "25kg" exists only as text in the title |
| Laundry Detergent 6L | 1 | one bottle — "6L" only in the title |
| Bottled Water Case (24pk) | 24 | 24 bottles |
| Egg Tray (30s) | 30 | 30 eggs |
| 3-in-1 Coffee Bulk Pack | 60 | 60 sachets |

So `quantity` is sometimes a count of items and sometimes a count of containers,
with the real measure buried in free text. The details screen prints "1 unit" for
the rice, which tells the student nothing.

And there is a sharper problem underneath. **30 eggs split 4 ways is 7.5 eggs.**
Nobody can collect half an egg. The split-cost work made the *money* reconcile;
the *goods* have never been checked at all, and a deal can currently be posted
that cannot physically be fulfilled.

## Decisions

**Replace `quantity` with `amount` + `unit`.** Not alongside — a 24-pack would
otherwise carry `quantity: 24` *and* `amount: 24, unit: bottles`, two fields that
must agree, which is two fields that will eventually disagree.

**Seven units, and the unit carries the divisibility rule.**

- **Continuous** (amount may be fractional): `kg`, `L`
- **Discrete** (amount must be whole): `pieces`, `packs`, `bottles`, `cans`,
  `sachets`

Divisibility is not a separate flag someone must remember to set — it falls out
of the unit the poster picks. Choosing "pieces" *is* saying the goods cannot be
halved.

`g` and `mL` are deliberately excluded. They would create two ways to spell the
same thing (`500 g` vs `0.5 kg`), leaving the feed inconsistent and search worse.
`amount` is a decimal, so the large unit covers every case with one canonical
spelling. Nobody bulk-buys 500 g of rice to split seven ways.

The discrete units all behave identically in the arithmetic. They exist so the
app can say "6 bottles" rather than "6 pieces".

**Goods that do not divide evenly are refused at post time.** "30 pieces across
4 slots leaves 7.5 each. Try 3 or 5 slots."

This mirrors the money decision, applied to the thing money cannot fix. There,
every student pays an identical share and the host absorbs the odd centavo — a
centavo is divisible and trivial. Goods are not. The only way to keep shares
equal is to stop the deal existing in a shape where they cannot be. The poster
holds the lever: slot count *is* portion size, and the app tells them which
counts work.

Rejected alternatives:

- **Warn but allow.** Honest, but hands the problem back to the students, which
  is what the app exists to prevent. It remains the escape hatch if blocking
  proves too strict in practice — a one-line change from here. Starting there
  and tightening later would retroactively invalidate deals people had posted,
  so blocking is also the easier direction to move *from*.
- **Allocate the remainder** (two students get 8 eggs, two get 7). Looks
  generous, but quietly makes the deal unfair: identical price, different goods.
  It then needs a rule for *who* gets the extra, inventing a new argument at
  pickup at the exact moment the app was meant to remove one.

**Known cost of refusing:** some deals become impossible. A 7-bottle pack has no
divisor between 2 and 50 except 7, so it could only be split 7 ways. In practice
this rarely bites — bulk goods are packaged in composite numbers precisely
because they are meant to be shared (24-pack: 2, 3, 4, 6, 8, 12; 30 eggs: 2, 3,
5, 6, 10, 15; 60 sachets: many). A prime-numbered pack is genuinely blocked, and
that is accepted.

## Architecture

### `DealUnit` — `lib/models/deal_unit.dart`

```dart
enum DealUnit {
  kg('kg', continuous: true),
  litre('L', continuous: true),
  pieces('pieces', continuous: false),
  packs('packs', continuous: false),
  bottles('bottles', continuous: false),
  cans('cans', continuous: false),
  sachets('sachets', continuous: false);

  final String label;
  final bool continuous;
  bool get discrete => !continuous;
}
```

### `PhysicalShare` — `lib/models/physical_share.dart`

The goods twin of `CostSplit`. Pure, no I/O.

```dart
class PhysicalShare {
  factory PhysicalShare.from({
    required double amount,
    required DealUnit unit,
    required int slots,
  });

  final double amount;
  final DealUnit unit;
  final int slots;

  double get amountPerShare;         // 25 / 7 = 3.571…
  bool get dividesEvenly;            // continuous: always. discrete: amount % slots == 0
  String get shareLabel;             // "3.57 kg" / "6 bottles"
  String get totalLabel;             // "25 kg" / "24 bottles"
  List<int> get workableSlotCounts;  // discrete: divisors within kMinDealSlots..kMaxDealSlots
}
```

Two edges it must handle:

- **A single item cannot be split.** `1 piece` has no divisor ≥ 2, so
  `workableSlotCounts` is empty and such a deal is refused outright.
- **A prime amount above the slot ceiling** (e.g. 97 pieces) likewise has no
  workable count in 2–50. Also refused, with an honest message rather than a
  suggestion it cannot make.

Continuous goods always divide, so `workableSlotCounts` is not consulted for them.

**Stored value.** `unit` persists as the enum's Dart `name` — `kg`, `litre`,
`pieces`, `packs`, `bottles`, `cans`, `sachets` — matching how `category` and
`status` already round-trip through `DealCategory.name` / `_statusValue`. So the
continuous units in SQL are `('kg', 'litre')`, not `('kg', 'L')`; `L` is the
display label only.

### Validation

Cross-field: the slot count is only valid *given* the amount and unit. Flutter
validators are closures, so the slots field's validator reads the amount and unit
controllers directly — the error stays on the field it belongs to.

The message names the fix: **"30 pieces across 4 slots leaves 7.5 each. Try 3 or
5 slots."** It suggests the nearest workable counts either side of what the poster
typed, rather than dumping every divisor.

Rules:

- `amount > 0`
- discrete → `amount` must be a whole number
- discrete → `amount % slots == 0`
- continuous → any slot count within the existing 2–50 bounds

### The database enforces it too

```sql
alter table public.deals
  add constraint deals_goods_divide_check check (
    unit in ('kg', 'litre')
    or (amount = floor(amount) and (amount::int) % total_slots = 0)
  );
```

This is the lesson from the `deal_feed` leak, applied deliberately. A client-side
check is a convenience, not a control — anything speaking to PostgREST can skip
it. If a deal that cannot be physically fulfilled must not exist, the database is
the thing that has to refuse it.

### Schema migration, in order

`deal_feed` selects `quantity`, so the column cannot be dropped while the view
depends on it. The sequence matters:

1. Add `amount numeric` and `unit text` to `deals`.
2. Backfill the seeded deals to their true measures.
3. Recreate `deal_feed` selecting `amount` and `unit` instead of `quantity`
   (keeping the hub-membership scoping added on 2026-07-14).
4. Drop `quantity`.
5. Add the constraints: `amount > 0`, `unit` in the seven, and the divisibility
   check above. Set both columns `NOT NULL`.

**The one real deal in the database is deleted, not migrated.** It is the "25kg
Rice Sack" test row created while verifying slot reservation. Its `quantity` is
1 and its real measure lives only in the title string, so migrating it would mean
parsing English out of free text to guess `25 kg` — the same prose-matching that
caused the auth bug on 2026-07-14. Deleting a test artifact is honest; guessing is
not. The delete cascades to its reservation row.

## Screens

**Create deal.** The "Quantity" field becomes **Amount** plus a unit dropdown.
Beneath the slots field, alongside the existing "Each student pays ₱128.58", sits
"Each student gets 3.57 kg" — or, when the goods do not divide, the blocking
error naming the workable slot counts.

**Deal details.** The meaningless "1 unit" pill becomes "25 kg". The cost card
gains the physical share beside the money, so "YOUR SHARE" answers both questions
a student actually has: what do I pay, and what do I get.

**Deal card.** Shows the per-share amount alongside the per-share price.

## Testing

`PhysicalShare` is pure arithmetic and tests cheaply:

- Continuous divides freely: 25 kg ÷ 7 → 3.571… kg, `dividesEvenly` true.
- Discrete divides evenly: 30 pieces ÷ 5 → 6 each.
- Discrete does not divide: 30 pieces ÷ 4 → `dividesEvenly` false.
- `workableSlotCounts` for 30 is [2, 3, 5, 6, 10, 15, 30]; for 24 is
  [2, 3, 4, 6, 8, 12, 24].
- A 1-piece deal has no workable count and is refused.
- A 97-piece deal (prime, above the ceiling) has no workable count and is refused.

Then the validator's message and suggestions, the form's live preview, and the
details display.

**The CHECK constraint is proven in SQL**, not only in Dart: an indivisible deal
must be rejected by Postgres when inserted directly, exactly as the reservation
RPCs were proven against the live project.

## Out of scope

- **Editing a deal after it is posted.** No edit flow exists today, and adding
  one here would drag in questions about what happens to students who already
  reserved a slot under the old numbers.
- **`rolls` as a unit.** Toilet paper is a plausible dorm bulk-buy, but `packs`
  covers it, and five discrete units is enough to ship. Adding it later is one
  enum entry and needs no migration, since discrete units behave identically.
