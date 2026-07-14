# Physical Share Breakdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tell a student what they physically receive from a bulk buy — 3.57 kg, 6 bottles — and refuse deals whose goods cannot be divided into equal shares.

**Architecture:** `quantity` (an int meaning two different things) is replaced by `amount` + `unit`. The unit carries the divisibility rule: choosing "pieces" *is* saying the goods cannot be halved. A pure `PhysicalShare` type mirrors the existing `CostSplit`. Deals whose goods do not divide evenly are refused at post time — in Postgres as well as in Dart, because a client-side check is a convenience, not a control.

**Tech Stack:** Flutter, Dart, `provider`, `supabase_flutter`, Postgres.

**Spec:** `docs/superpowers/specs/2026-07-15-physical-share-breakdown-design.md`

---

## Critical context

**Enums persist by their Dart `name`.** `DealCategory.grocery` is stored as `'grocery'`. So `DealUnit.litre` stores as `'litre'`, **not** `'l'` or `'L'` — `L` is the display label only. Getting this wrong makes the SQL constraint treat litres as a *discrete* unit and block valid detergent deals.

**The migration has a forced order.** `deal_feed` selects `d.quantity`. Postgres will not let you drop a column a view depends on. Add columns → backfill → recreate the view → drop `quantity` → add constraints.

**Migrations are applied by hand** in the Supabase SQL editor. Task 1 writes the file; the engineer must then hand the SQL to the user and wait for confirmation. Do not assume a `supabase db push` pipeline.

**The Supabase SQL editor mangles bare `$$` dollar-quoting.** Use named tags (`$fn$`) for any function body. (No functions in this plan, but the editor also chokes when many statements are pasted at once — offer the SQL in chunks if it errors.)

**The one real deal in the database is deleted, not migrated.** It is a "25kg Rice Sack" test row whose real measure lives only in its title string. Deleting cascades to its reservation row.

**Existing bounds:** `kMinDealSlots = 2`, `kMaxDealSlots = 50` in `create_deal_viewmodel.dart`.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/models/deal_unit.dart` | **New.** `DealUnit` enum; each unit knows if it is continuous. |
| `lib/models/physical_share.dart` | **New.** Pure goods arithmetic; the twin of `CostSplit`. |
| `test/models/physical_share_test.dart` | **New.** Unit tests, including the indivisible edges. |
| `lib/models/deal.dart` | `quantity` → `amount` + `unit` on both `Deal` and `DealDraft`; add `physicalShare`. |
| `lib/data/repositories/deal_repository.dart` | Map `amount`/`unit` from rows; send them on insert; reseed the mock deals with real measures. |
| `lib/ui/split_board/create_deal_viewmodel.dart` | `validateAmount`, cross-field slot validation, `previewShare`. |
| `lib/ui/split_board/create_deal_screen.dart` | Amount field + unit dropdown; live physical-share preview. |
| `lib/ui/split_board/deal_details_screen.dart` | "25 kg" pill; physical share on the cost card. |
| `lib/ui/split_board/widgets/deal_card.dart` | Per-share amount beside the per-share price. |
| `supabase/migrations/20260715010000_add_deal_amount_and_unit.sql` | **New.** The schema change, in order. |

---

### Task 1: `DealUnit` and `PhysicalShare`

**Files:**
- Create: `lib/models/deal_unit.dart`
- Create: `lib/models/physical_share.dart`
- Test: `test/models/physical_share_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/models/physical_share_test.dart`:

```dart
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/physical_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continuous goods divide freely', () {
    final share = PhysicalShare.from(
      amount: 25,
      unit: DealUnit.kg,
      slots: 7,
    );

    expect(share.dividesEvenly, isTrue);
    expect(share.amountPerShare, closeTo(3.5714, 0.0001));
    expect(share.shareLabel, '3.57 kg');
    expect(share.totalLabel, '25 kg');
  });

  test('discrete goods that divide evenly give whole shares', () {
    final share = PhysicalShare.from(
      amount: 30,
      unit: DealUnit.pieces,
      slots: 5,
    );

    expect(share.dividesEvenly, isTrue);
    expect(share.amountPerShare, 6);
    expect(share.shareLabel, '6 pieces');
  });

  test('discrete goods that do not divide are caught', () {
    // 30 eggs across 4 slots is 7.5 eggs, and nobody can collect half an egg.
    final share = PhysicalShare.from(
      amount: 30,
      unit: DealUnit.pieces,
      slots: 4,
    );

    expect(share.dividesEvenly, isFalse);
  });

  test('a single share reads in the singular', () {
    final share = PhysicalShare.from(
      amount: 4,
      unit: DealUnit.bottles,
      slots: 4,
    );

    expect(share.shareLabel, '1 bottle');
  });

  test('lists the slot counts that actually work', () {
    final thirty = PhysicalShare.from(
      amount: 30,
      unit: DealUnit.pieces,
      slots: 4,
    );
    expect(thirty.workableSlotCounts, [2, 3, 5, 6, 10, 15, 30]);

    final twentyFour = PhysicalShare.from(
      amount: 24,
      unit: DealUnit.bottles,
      slots: 5,
    );
    expect(twentyFour.workableSlotCounts, [2, 3, 4, 6, 8, 12, 24]);
  });

  test('a continuous deal needs no suggestions, it always divides', () {
    final share = PhysicalShare.from(amount: 25, unit: DealUnit.kg, slots: 7);

    expect(share.workableSlotCounts, isEmpty);
    expect(share.dividesEvenly, isTrue);
  });

  test('a single item cannot be split at all', () {
    final share = PhysicalShare.from(
      amount: 1,
      unit: DealUnit.pieces,
      slots: 2,
    );

    expect(share.dividesEvenly, isFalse);
    expect(share.workableSlotCounts, isEmpty);
    expect(share.canBeSplit, isFalse);
  });

  test('a prime amount above the slot ceiling cannot be split either', () {
    // 97 is prime, and 97 > kMaxDealSlots, so no count in 2..50 divides it.
    final share = PhysicalShare.from(
      amount: 97,
      unit: DealUnit.pieces,
      slots: 4,
    );

    expect(share.workableSlotCounts, isEmpty);
    expect(share.canBeSplit, isFalse);
  });

  test('rejects an amount of nothing', () {
    expect(
      () => PhysicalShare.from(amount: 0, unit: DealUnit.kg, slots: 4),
      throwsArgumentError,
    );
  });

  test('units know whether they can be halved', () {
    expect(DealUnit.kg.continuous, isTrue);
    expect(DealUnit.litre.continuous, isTrue);
    expect(DealUnit.pieces.discrete, isTrue);
    expect(DealUnit.bottles.discrete, isTrue);

    // Stored by Dart name, as DealCategory already is: 'litre', not 'L'.
    expect(DealUnit.litre.name, 'litre');
    expect(DealUnit.litre.label, 'L');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/models/physical_share_test.dart`
Expected: FAIL — neither file exists.

- [ ] **Step 3: Write `DealUnit`**

Create `lib/models/deal_unit.dart`:

```dart
/// What a bulk buy is measured in — and, because of that, whether it can be
/// divided at all.
///
/// The unit carries the rule rather than a separate flag someone has to
/// remember to set: a poster choosing "pieces" has already said the goods
/// cannot be halved.
///
/// Grams and millilitres are deliberately absent. They would give two ways to
/// spell the same buy (500 g vs 0.5 kg), and the amount is a decimal, so the
/// large unit covers every case with one canonical spelling.
enum DealUnit {
  kg('kg', 'kg', continuous: true),
  litre('L', 'L', continuous: true),
  pieces('pieces', 'piece', continuous: false),
  packs('packs', 'pack', continuous: false),
  bottles('bottles', 'bottle', continuous: false),
  cans('cans', 'can', continuous: false),
  sachets('sachets', 'sachet', continuous: false);

  const DealUnit(this.label, this.singularLabel, {required this.continuous});

  /// Shown next to an amount: "25 kg", "24 bottles".
  final String label;

  /// Shown when there is exactly one: "1 bottle". Weights and volumes never
  /// pluralise, so their two labels are the same.
  final String singularLabel;

  /// Weights and volumes divide freely. Countable things do not.
  final bool continuous;

  bool get discrete => !continuous;
}
```

- [ ] **Step 4: Write `PhysicalShare`**

Create `lib/models/physical_share.dart`:

```dart
import 'deal_unit.dart';

/// The smallest and largest splits a deal may be posted with. Mirrors
/// kMinDealSlots / kMaxDealSlots in create_deal_viewmodel.dart, which bound the
/// slot count itself; these bound the slot counts we are willing to *suggest*.
const int _minSuggestedSlots = 2;
const int _maxSuggestedSlots = 50;

/// What one student physically receives from a bulk buy.
///
/// The goods twin of [CostSplit]. Money and goods behave differently and the
/// difference is the whole point of this type: an odd centavo can be rounded up
/// and absorbed by the host, but nobody can collect half an egg. So where the
/// money always reconciles, the goods sometimes simply cannot be divided, and
/// the deal must not exist in that shape.
class PhysicalShare {
  PhysicalShare._({
    required this.amount,
    required this.unit,
    required this.slots,
  });

  factory PhysicalShare.from({
    required double amount,
    required DealUnit unit,
    required int slots,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'A bulk buy needs an amount above zero.',
      );
    }
    if (slots < 1) {
      throw ArgumentError.value(slots, 'slots', 'A split needs at least one slot.');
    }
    return PhysicalShare._(amount: amount, unit: unit, slots: slots);
  }

  final double amount;
  final DealUnit unit;
  final int slots;

  double get amountPerShare => amount / slots;

  /// Weights and volumes always divide. Countable goods only divide when the
  /// slot count is a factor of the amount.
  bool get dividesEvenly {
    if (unit.continuous) return true;
    if (amount != amount.roundToDouble()) return false;
    return amount.round() % slots == 0;
  }

  /// Whether this amount can be split at *any* allowed slot count. False for a
  /// single item, and for a prime amount larger than the slot ceiling — there
  /// is no honest suggestion to make in either case.
  bool get canBeSplit => unit.continuous || workableSlotCounts.isNotEmpty;

  /// The slot counts that divide these goods evenly. Empty for continuous
  /// goods, which need no suggestion because every count works.
  List<int> get workableSlotCounts {
    if (unit.continuous) return const [];
    if (amount != amount.roundToDouble()) return const [];

    final whole = amount.round();
    return [
      for (var slots = _minSuggestedSlots; slots <= _maxSuggestedSlots; slots++)
        if (whole % slots == 0) slots,
    ];
  }

  /// "3.57 kg", "6 bottles", "1 bottle".
  String get shareLabel => _label(amountPerShare);

  /// "25 kg", "24 bottles".
  String get totalLabel => _label(amount);

  String _label(double value) {
    final isWhole = value == value.roundToDouble();
    final text = isWhole ? value.round().toString() : value.toStringAsFixed(2);
    final unitLabel = isWhole && value.round() == 1
        ? unit.singularLabel
        : unit.label;
    return '$text $unitLabel';
  }
}
```

- [ ] **Step 5: Run and watch it pass**

Run: `flutter test test/models/physical_share_test.dart`
Expected: PASS, 10 tests.

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/models/deal_unit.dart lib/models/physical_share.dart test/models/physical_share_test.dart
git commit -m "feat: add DealUnit and PhysicalShare, the goods twin of CostSplit"
```

---

### Task 2: `Deal` and `DealDraft` carry amount and unit

**Files:**
- Modify: `lib/models/deal.dart`
- Test: `test/models/physical_share_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append to `test/models/physical_share_test.dart`, adding
`import 'package:bulk_buying_companion/models/deal.dart';` to its imports:

```dart
  test('a deal knows what each student physically gets', () {
    const deal = Deal(
      id: 'rice',
      hubId: 'colon',
      title: '25kg Rice Sack',
      category: DealCategory.grocery,
      totalPrice: 900,
      amount: 25,
      unit: DealUnit.kg,
      availableSlots: 6,
      totalSlots: 7,
      pickupLocation: 'USJR Main Gate',
      status: DealStatus.open,
    );

    expect(deal.physicalShare.shareLabel, '3.57 kg');
    expect(deal.physicalShare.totalLabel, '25 kg');
    // The money and the goods answer the two questions a student actually has.
    expect(deal.priceLabel, 'P128.58/share');
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/models/physical_share_test.dart`
Expected: FAIL — `Deal` has no named parameter `amount`; `quantity` is required.

- [ ] **Step 3: Change the model**

In `lib/models/deal.dart`, add `import 'deal_unit.dart';` and
`import 'physical_share.dart';` at the top.

On `Deal`: replace the `required this.quantity,` constructor entry with
`required this.amount,` and `required this.unit,`. Replace the field and its
comment:

```dart
  /// How much the bulk buy covers, and in what. The unit also decides whether
  /// the goods can be divided at all — see [PhysicalShare].
  final double amount;
  final DealUnit unit;
```

Add the getter next to `costSplit`:

```dart
  /// What one student physically receives. Sits beside [costSplit]: together
  /// they answer the two questions a student has — what do I pay, what do I get.
  PhysicalShare get physicalShare =>
      PhysicalShare.from(amount: amount, unit: unit, slots: totalSlots);
```

On `DealDraft`: the same substitution — replace `required this.quantity,` with
`required this.amount,` / `required this.unit,`, and replace
`final int quantity;` with `final double amount;` and `final DealUnit unit;`.

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: **FAIL, widely.** Every construction of `Deal` or `DealDraft` in `lib/`
and `test/` still passes `quantity`. That is expected at this point — Task 3
fixes the repository and Task 4 the UI. Do not try to fix them all here.

To keep this task self-contained, only make `lib/models/deal.dart` and
`test/models/physical_share_test.dart` compile and pass:

Run: `flutter test test/models/physical_share_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

The tree does not fully compile yet; that is resolved in Task 3. Commit anyway so
the model change is a reviewable step on its own.

```bash
git add lib/models/deal.dart test/models/physical_share_test.dart
git commit -m "feat: a deal is measured in an amount and a unit, not a bare quantity"
```

---

### Task 3: The repository speaks amount and unit

**Files:**
- Modify: `lib/data/repositories/deal_repository.dart`
- Modify: `test/data/repositories/supabase_deal_repository_test.dart`

- [ ] **Step 1: Read the file**

READ `lib/data/repositories/deal_repository.dart` in full. Note:
- the top-level `dealFromRow` mapper (it reads `row['quantity']`),
- `MockDealRepository`'s five seeded deals,
- `SupabaseDealRepository.createDeal`'s insert map,
- `_dealCategoryFromValue` / `_dealStatusFromValue`, whose shape you will copy.

- [ ] **Step 2: Update the mapper and the insert**

In `dealFromRow`, replace the `quantity:` line with:

```dart
    amount: (row['amount'] as num).toDouble(),
    unit: _dealUnitFromValue(row['unit'] as String),
```

Add the value mapper alongside the existing ones, matching their style:

```dart
DealUnit _dealUnitFromValue(String value) {
  return DealUnit.values.firstWhere(
    (unit) => unit.name == value,
    orElse: () => throw StateError('Unknown deal unit "$value".'),
  );
}
```

In `SupabaseDealRepository.createDeal`, replace `'quantity': draft.quantity,`
with:

```dart
        'amount': draft.amount,
        // Stored by Dart name, as category is: 'litre', not 'L'.
        'unit': draft.unit.name,
```

In `MockDealRepository.createDeal`, replace `quantity: draft.quantity,` with:

```dart
      amount: draft.amount,
      unit: draft.unit,
```

Add `import '../../models/deal_unit.dart';` to the file.

- [ ] **Step 3: Reseed the mock deals with their real measures**

The five seeded deals currently carry a `quantity` that means different things.
Give each its true measure — this is exactly the confusion the card exists to fix:

| Deal | was | becomes |
|---|---|---|
| `25kg Rice Sack — Split 5 ways` | `quantity: 1` | `amount: 25, unit: DealUnit.kg` |
| `Bottled Water Case (24pk)` | `quantity: 24` | `amount: 24, unit: DealUnit.bottles` |
| `Laundry Detergent 6L` | `quantity: 1` | `amount: 6, unit: DealUnit.litre` |
| `Egg Tray (30s) — Split 3 ways` | `quantity: 30` | `amount: 30, unit: DealUnit.pieces` |
| `3-in-1 Coffee Bulk Pack` | `quantity: 60` | `amount: 60, unit: DealUnit.sachets` |

**Check each against its slot count.** The seeded deals must obey the rule the app
now enforces, or the mock will hold deals the real app would refuse:
- rice 25 kg / 5 slots — continuous, always fine
- water 24 bottles / 4 slots — 24 % 4 == 0, fine
- detergent 6 L / 3 slots — continuous, fine
- eggs 30 pieces / 3 slots — 30 % 3 == 0, fine
- coffee 60 sachets / 6 slots — 60 % 6 == 0, fine

All five divide. If any had not, the seed would need its slot count changed.

- [ ] **Step 4: Fix the repository test**

In `test/data/repositories/supabase_deal_repository_test.dart`, the fake gateway
echoes the inserted row back. Any `quantity` in its fixture rows becomes
`'amount'` and `'unit'` (e.g. `'amount': 25, 'unit': 'kg'`). Any assertion on
the insert map's `quantity` becomes an assertion on `amount` and `unit`.

READ the file and adjust its fixtures; do not guess their shape.

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: still failing in the **UI** tests and `create_deal_viewmodel`, which
Task 4 fixes. But `test/data/repositories/` and `test/models/` must now pass:

Run: `flutter test test/data test/models`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/deal_repository.dart test/data/repositories/supabase_deal_repository_test.dart
git commit -m "feat: map a deal's amount and unit, and give the seeded deals real measures"
```

---

### Task 4: Validation refuses goods that cannot be divided

**Files:**
- Modify: `lib/ui/split_board/create_deal_viewmodel.dart`
- Test: `test/ui/split_board/create_deal_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside the existing `main()` of
`test/ui/split_board/create_deal_viewmodel_test.dart`, adding
`import 'package:bulk_buying_companion/models/deal_unit.dart';` and
`import 'package:bulk_buying_companion/models/physical_share.dart';`:

```dart
  test('rejects an amount that is not a positive number', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(viewModel.validateAmount('', DealUnit.kg), 'Enter the amount.');
    expect(
      viewModel.validateAmount('abc', DealUnit.kg),
      'Amount must be a number.',
    );
    expect(
      viewModel.validateAmount('0', DealUnit.kg),
      'Amount must be more than 0.',
    );
    expect(viewModel.validateAmount('25', DealUnit.kg), isNull);
  });

  test('countable goods must come in whole numbers', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    // Half a bottle is not a thing you can buy.
    expect(
      viewModel.validateAmount('24.5', DealUnit.bottles),
      'Bottles come in whole numbers.',
    );
    expect(viewModel.validateAmount('24', DealUnit.bottles), isNull);

    // Weights and volumes are happy to be fractional.
    expect(viewModel.validateAmount('25.5', DealUnit.kg), isNull);
  });

  test('refuses a slot count that cannot divide the goods', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    // 30 eggs across 4 slots is 7.5 eggs each, which nobody can collect.
    expect(
      viewModel.validateTotalSlots('4', amount: '30', unit: DealUnit.pieces),
      '30 pieces across 4 slots leaves 7.5 each. Try 3 or 5 slots.',
    );

    // 5 works, and so does anything else that divides 30.
    expect(
      viewModel.validateTotalSlots('5', amount: '30', unit: DealUnit.pieces),
      isNull,
    );
  });

  test('a weight divides at any slot count', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalSlots('7', amount: '25', unit: DealUnit.kg),
      isNull,
    );
  });

  test('says plainly when goods cannot be split at all', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalSlots('2', amount: '1', unit: DealUnit.pieces),
      'A single piece cannot be split.',
    );
  });

  test('still enforces the slot bounds', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalSlots('1', amount: '25', unit: DealUnit.kg),
      'Slots must be at least $kMinDealSlots.',
    );
    expect(
      viewModel.validateTotalSlots(
        '${kMaxDealSlots + 1}',
        amount: '25',
        unit: DealUnit.kg,
      ),
      'Keep it to $kMaxDealSlots slots or fewer.',
    );
  });

  test('previews what each student physically gets', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    final share = viewModel.previewShare(
      amount: '25',
      unit: DealUnit.kg,
      totalSlots: '7',
    );

    expect(share, isNotNull);
    expect(share!.shareLabel, '3.57 kg');

    expect(
      viewModel.previewShare(amount: '', unit: DealUnit.kg, totalSlots: '7'),
      isNull,
    );
  });
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/ui/split_board/create_deal_viewmodel_test.dart`
Expected: FAIL — `validateAmount` and `previewShare` are not defined, and
`validateTotalSlots` takes no `amount`/`unit`.

- [ ] **Step 3: Write the implementation**

In `lib/ui/split_board/create_deal_viewmodel.dart`, add:

```dart
import '../../models/deal_unit.dart';
import '../../models/physical_share.dart';
```

**Delete `validateQuantity`** entirely — nothing calls it after Task 5. Replace
it with:

```dart
  String? validateAmount(String? value, DealUnit unit) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter the amount.';

    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) return 'Amount must be a number.';
    if (parsed <= 0) return 'Amount must be more than 0.';

    // You cannot buy half a bottle. Weights and volumes are happy to be
    // fractional; countable things are not.
    if (unit.discrete && parsed != parsed.roundToDouble()) {
      final noun = unit.label[0].toUpperCase() + unit.label.substring(1);
      return '$noun come in whole numbers.';
    }
    return null;
  }
```

Replace `validateTotalSlots` with a version that also knows the goods. The slot
count is only valid *given* the amount and unit, so this is a cross-field check:

```dart
  /// The slot count is only meaningful against the goods being split, so this
  /// takes them too. Flutter validators are closures, so the screen can hand
  /// over the other fields and the error still lands on the slots field.
  String? validateTotalSlots(
    String? value, {
    required String? amount,
    required DealUnit unit,
  }) {
    final error = _validateWholeNumber(value, label: 'Slots', min: kMinDealSlots);
    if (error != null) return error;

    final slots = int.parse(value!.trim());
    if (slots < kMinDealSlots) {
      return 'A split needs at least $kMinDealSlots slots.';
    }
    if (slots > kMaxDealSlots) {
      return 'Keep it to $kMaxDealSlots slots or fewer.';
    }

    // Without a usable amount there is nothing to divide yet; the amount field
    // is already complaining, and two errors for one mistake helps nobody.
    final parsedAmount = double.tryParse((amount ?? '').trim());
    if (parsedAmount == null || !parsedAmount.isFinite || parsedAmount <= 0) {
      return null;
    }

    final share = PhysicalShare.from(
      amount: parsedAmount,
      unit: unit,
      slots: slots,
    );
    if (share.dividesEvenly) return null;

    if (!share.canBeSplit) {
      return 'A single ${unit.singularLabel} cannot be split.';
    }

    return '${share.totalLabel} across $slots slots leaves '
        '${_trimmed(share.amountPerShare)} each. '
        'Try ${_suggest(share.workableSlotCounts, slots)}.';
  }

  /// The nearest workable counts either side of what the poster typed. Naming
  /// every divisor of 60 would be a wall of numbers, not a suggestion.
  String _suggest(List<int> workable, int wanted) {
    final below = workable.where((count) => count < wanted).lastOrNull;
    final above = workable.where((count) => count > wanted).firstOrNull;

    final options = [
      if (below != null) below,
      if (above != null) above,
    ];
    if (options.isEmpty) return '${workable.first} slots';
    if (options.length == 1) return '${options.first} slots';
    return '${options.first} or ${options.last} slots';
  }

  /// 7.5, not 7.50; 6, not 6.0.
  String _trimmed(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }
```

Add the live preview beside the existing `previewSplit`:

```dart
  /// What each student physically receives, shown live beside what they pay.
  /// Null — never an exception — while the inputs are unusable: this runs on
  /// every keystroke from inside build.
  PhysicalShare? previewShare({
    required String? amount,
    required DealUnit unit,
    required String? totalSlots,
  }) {
    final parsedAmount = double.tryParse((amount ?? '').trim());
    final slots = int.tryParse((totalSlots ?? '').trim());
    if (parsedAmount == null || slots == null) return null;
    if (!parsedAmount.isFinite || parsedAmount <= 0) return null;
    if (slots < kMinDealSlots || slots > kMaxDealSlots) return null;

    return PhysicalShare.from(amount: parsedAmount, unit: unit, slots: slots);
  }
```

`lastOrNull` / `firstOrNull` come from `package:collection`. If it is not already
a dependency, use explicit loops instead of adding one for two calls — check
`pubspec.yaml` first and report which you did.

- [ ] **Step 4: Run and watch it pass**

Run: `flutter test test/ui/split_board/create_deal_viewmodel_test.dart`
Expected: PASS. The pre-existing tests in this file that call `validateTotalSlots`
with one argument will not compile — update them to pass `amount:` and `unit:`
(e.g. `amount: '25', unit: DealUnit.kg`, which always divides and so does not
change what they assert).

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/split_board/create_deal_viewmodel.dart test/ui/split_board/create_deal_viewmodel_test.dart
git commit -m "feat: refuse a slot count that cannot divide the goods, and say which ones can"
```

---

### Task 5: The create-deal form

**Files:**
- Modify: `lib/ui/split_board/create_deal_screen.dart`
- Test: `test/ui/split_board/create_deal_screen_test.dart`

- [ ] **Step 1: Read both files**

READ `lib/ui/split_board/create_deal_screen.dart` and
`test/ui/split_board/create_deal_screen_test.dart` in full. Note the real helper
names in the test (`pumpScreen`, `fillForm`) and the existing `_SplitPreview`
widget and `_CategorySelector`, whose shape the unit dropdown should echo.

The quantity field is at roughly line 150, keyed `deal-quantity-field`, sitting
in a `Row` beside the total-price field.

- [ ] **Step 2: Write the failing tests**

Append to `test/ui/split_board/create_deal_screen_test.dart`, using the file's
real helpers. `fillForm` will need an `amount` parameter in place of `quantity`,
and a way to choose the unit — extend it rather than writing a parallel helper.

```dart
  testWidgets('shows what each student physically gets', (tester) async {
    await pumpScreen(tester, MockDealRepository());

    await fillForm(tester, totalPrice: '900', amount: '25', totalSlots: '7');

    expect(find.text('Each student pays P128.58'), findsOneWidget);
    expect(find.byKey(const Key('deal-share-preview')), findsOneWidget);
    expect(find.text('Each student gets 3.57 kg'), findsOneWidget);
  });

  testWidgets('refuses goods that will not divide, and names what will', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());

    // 30 pieces across 4 slots is 7.5 each.
    await fillForm(
      tester,
      title: 'Egg Tray',
      totalPrice: '255',
      amount: '30',
      unit: DealUnit.pieces,
      totalSlots: '4',
      pickupLocation: 'USJR Main Gate',
    );

    await tester.tap(find.byKey(const Key('deal-submit-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('30 pieces across 4 slots leaves 7.5 each. Try 3 or 5 slots.'),
      findsOneWidget,
    );
  });
```

- [ ] **Step 3: Run and watch them fail**

Run: `flutter test test/ui/split_board/create_deal_screen_test.dart`
Expected: FAIL — no amount field, no unit selector, no share preview.

- [ ] **Step 4: Write the implementation**

In `lib/ui/split_board/create_deal_screen.dart`:

Add `import '../../models/deal_unit.dart';`.

Replace the `_quantityController` with `_amountController` (rename the field, its
`dispose()` entry, and its uses), and add state for the unit:

```dart
  final _amountController = TextEditingController();
  DealUnit _unit = DealUnit.kg;
```

Replace the quantity `TextFormField` with the amount field. It must rebuild the
preview on change, and its validator needs the unit:

```dart
                        Expanded(
                          child: TextFormField(
                            key: const Key('deal-amount-field'),
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              hintText: '25',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                viewModel.validateAmount(value, _unit),
                          ),
                        ),
```

Add the unit selector directly beneath that `Row`, echoing the existing
`_CategorySelector`'s look:

```dart
                    const SizedBox(height: 12),
                    _UnitSelector(
                      unit: _unit,
                      onChanged: viewModel.isSubmitting
                          ? null
                          : (unit) => setState(() => _unit = unit),
                    ),
```

```dart
/// Weights and volumes divide freely; countable goods do not. Picking the unit
/// is how the poster tells the app which kind of thing this is.
class _UnitSelector extends StatelessWidget {
  const _UnitSelector({required this.unit, required this.onChanged});

  final DealUnit unit;
  final ValueChanged<DealUnit>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in DealUnit.values)
          ChoiceChip(
            key: Key('deal-unit-${option.name}'),
            label: Text(option.label),
            selected: option == unit,
            onSelected: onChanged == null
                ? null
                : (selected) {
                    if (selected) onChanged!(option);
                  },
          ),
      ],
    );
  }
}
```

Point the slots field's validator at the goods:

```dart
                      validator: (value) => viewModel.validateTotalSlots(
                        value,
                        amount: _amountController.text,
                        unit: _unit,
                      ),
```

Add the share preview directly under the existing `_SplitPreview`:

```dart
                    _SharePreview(
                      share: viewModel.previewShare(
                        amount: _amountController.text,
                        unit: _unit,
                        totalSlots: _totalSlotsController.text,
                      ),
                    ),
```

```dart
/// The other half of what a student needs to know: not just what they pay, but
/// what they actually get.
class _SharePreview extends StatelessWidget {
  const _SharePreview({required this.share});

  final PhysicalShare? share;

  @override
  Widget build(BuildContext context) {
    final share = this.share;
    if (share == null || !share.dividesEvenly) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'Each student gets ${share.shareLabel}',
            key: const Key('deal-share-preview'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
```

Add `import '../../models/physical_share.dart';`.

Finally, in the submit handler, replace
`quantity: int.parse(_quantityController.text.trim()),` in the `DealDraft` with:

```dart
      amount: double.parse(_amountController.text.trim()),
      unit: _unit,
```

- [ ] **Step 5: Run the full suite and the analyzer**

Run: `flutter test`
Expected: PASS, everything. All the earlier tasks' breakage is resolved by now.
If a pre-existing test still fails, read it and report exactly which.

Run: `flutter analyze`
Expected: no issues, and no unused `validateQuantity` left behind.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/split_board/create_deal_screen.dart test/ui/split_board/create_deal_screen_test.dart
git commit -m "feat: post a deal in an amount and a unit, and see the share before publishing"
```

---

### Task 6: Show the share on the board and the details screen

**Files:**
- Modify: `lib/ui/split_board/deal_details_screen.dart`
- Modify: `lib/ui/split_board/widgets/deal_card.dart`
- Test: `test/ui/split_board/deal_details_screen_test.dart`
- Test: `test/ui/split_board/deal_card_test.dart`

- [ ] **Step 1: Read the files**

READ all four. In `deal_details_screen.dart` the meaningless unit pill is around
line 72 (`'${deal.quantity} ${deal.quantity == 1 ? 'unit' : 'units'}'`), and
`_CostCard` holds the "YOUR SHARE" figure. In `deal_card.dart`, `deal.priceLabel`
is the headline at ~line 61.

Note the real fixtures in both test files — they construct `Deal` directly and
will need `amount`/`unit` in place of `quantity`.

- [ ] **Step 2: Write the failing tests**

In `test/ui/split_board/deal_details_screen_test.dart`, using its real helper:

```dart
  testWidgets('says what the buy is and what a share of it is', (tester) async {
    await pumpDetails(
      tester,
      _deal(amount: 25, unit: DealUnit.kg, totalPrice: 900, totalSlots: 7),
    );
    await tester.pumpAndSettle();

    // The whole buy, not a meaningless "1 unit".
    expect(find.text('25 kg'), findsOneWidget);
    // And what this student walks away with.
    expect(find.byKey(const Key('detail-physical-share')), findsOneWidget);
    expect(find.text('3.57 kg'), findsOneWidget);
  });
```

In `test/ui/split_board/deal_card_test.dart`:

```dart
  testWidgets('shows the share beside the price', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DealCard(
            deal: _deal(
              amount: 24,
              unit: DealUnit.bottles,
              totalPrice: 380,
              totalSlots: 4,
            ),
          ),
        ),
      ),
    );

    expect(find.text('P95/share'), findsOneWidget);
    expect(find.text('6 bottles each'), findsOneWidget);
  });
```

Adapt `_deal` in each file to take `amount` and `unit`; read the existing helper
before changing it.

- [ ] **Step 3: Run and watch them fail**

Run: `flutter test test/ui/split_board/deal_details_screen_test.dart test/ui/split_board/deal_card_test.dart`
Expected: FAIL — the pill still says "units", no `detail-physical-share`, no
"6 bottles each".

- [ ] **Step 4: Write the implementation**

In `deal_details_screen.dart`, replace the unit pill:

```dart
                      _Pill(label: deal.physicalShare.totalLabel),
```

In `_CostCard`, beneath the existing "YOUR SHARE" price, add the goods so the
card answers both questions at once:

```dart
                    Text(
                      deal.physicalShare.shareLabel,
                      key: const Key('detail-physical-share'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
```

Place it directly after the `formatPeso(deal.pricePerShare)` `Text`, inside the
same `Column`, with a `const SizedBox(height: 2)` between them.

In `deal_card.dart`, beneath `deal.priceLabel`, add:

```dart
                    Text(
                      '${deal.physicalShare.shareLabel} each',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
```

- [ ] **Step 5: Run the full suite and the analyzer**

Run: `flutter test`
Expected: PASS, everything.

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/split_board/deal_details_screen.dart lib/ui/split_board/widgets/deal_card.dart test/ui/split_board/deal_details_screen_test.dart test/ui/split_board/deal_card_test.dart
git commit -m "feat: show what a student receives, not just what they pay"
```

---

### Task 7: The migration

**Files:**
- Create: `supabase/migrations/20260715010000_add_deal_amount_and_unit.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260715010000_add_deal_amount_and_unit.sql`:

```sql
-- A deal's real measure lived only as text in its title: "25kg Rice Sack" was
-- stored as quantity 1. So the app could tell a student what they pay and had no
-- idea what they receive. amount + unit replaces quantity, and the unit carries
-- the divisibility rule -- 'pieces' says the goods cannot be halved.

alter table public.deals
  add column if not exists amount numeric,
  add column if not exists unit text;

-- The one real row is a test deal ("25kg Rice Sack") whose measure exists only
-- in its title. Migrating it would mean parsing English out of free text to
-- guess "25 kg", which is the same prose-matching that caused an auth bug on
-- 2026-07-14. Delete it instead; the reservation row cascades.
delete from public.deals where amount is null;

alter table public.deals
  alter column amount set not null,
  alter column unit set not null;

alter table public.deals
  add constraint deals_amount_check check (amount > 0);

alter table public.deals
  add constraint deals_unit_check check (
    unit in ('kg', 'litre', 'pieces', 'packs', 'bottles', 'cans', 'sachets')
  );

-- The rule the whole card exists for. 30 eggs across 4 slots is 7.5 eggs, and
-- nobody can collect half an egg.
--
-- Enforced here and not only in Dart, deliberately: a client-side check is a
-- convenience, not a control -- anything speaking to PostgREST can skip it. If a
-- deal that cannot be physically fulfilled must not exist, the database is the
-- thing that has to refuse it.
alter table public.deals
  add constraint deals_goods_divide_check check (
    unit in ('kg', 'litre')
    or (amount = floor(amount) and (amount::int) % total_slots = 0)
  );

-- deal_feed selects quantity, so the view has to stop depending on the column
-- before it can be dropped. Keeps the hub-membership scoping added on
-- 2026-07-14: a view runs with its owner's rights and ignores RLS on the tables
-- underneath, so the view itself is the security boundary.
create or replace view public.deal_feed as
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
  d.status,
  d.closes_at,
  d.created_at,
  p.display_name as host_name
from public.deals d
left join public.profiles p on p.user_id = d.created_by
where exists (
  select 1
  from public.hub_memberships m
  where m.hub_id = d.hub_id
    and m.user_id = (select auth.uid())
);

grant select on public.deal_feed to authenticated;

alter table public.deals drop column quantity;
```

**Note the ordering trap:** `create or replace view` cannot drop a column from an
existing view's output. Because the old `deal_feed` has `quantity` in its select
list and the new one does not, `create or replace` will fail with *"cannot change
name of view column"*. The view must be **dropped and recreated**, not replaced.
Change the statement to:

```sql
drop view if exists public.deal_feed;
create view public.deal_feed as
...
```

Use `drop view` + `create view` in the file. `create or replace` only works when
the column list is unchanged or purely appended.

- [ ] **Step 2: Hand the SQL to the user**

The repo has no migration pipeline — migrations are applied by hand in the
Supabase SQL editor. Post the file's contents and ask the user to run it, then
confirm before continuing.

Warn them plainly what it does to their data: **it deletes the "25kg Rice Sack"
test deal** (agreed in the spec — it is a test artifact whose measure cannot be
recovered), and its reservation row cascades away with it. The Split Board will
be empty afterwards, which is expected; the next deal posted exercises the new
amount + unit flow.

If the editor errors on the whole paste, give it to them in two chunks: the
`alter table` statements, then the view.

- [ ] **Step 3: Prove the database refuses an indivisible deal**

This is the claim the constraint exists for, and no Dart test can prove it. Ask
the user to run:

```sql
do $test$
declare
  v_hub  text;
  v_user uuid;
begin
  select hub_id, user_id into v_hub, v_user from public.hub_memberships limit 1;

  begin
    insert into public.deals (
      hub_id, created_by, title, category, total_price,
      amount, unit, total_slots, available_slots, pickup_location, status
    ) values (
      v_hub, v_user, 'Egg Tray', 'grocery', 255,
      30, 'pieces', 4, 4, 'USJR Main Gate', 'open'
    );
    raise notice 'FAIL: an indivisible deal was accepted';
  exception when check_violation then
    raise notice 'PASS: 30 pieces across 4 slots refused';
  end;

  begin
    insert into public.deals (
      hub_id, created_by, title, category, total_price,
      amount, unit, total_slots, available_slots, pickup_location, status
    ) values (
      v_hub, v_user, 'Rice Sack', 'grocery', 900,
      25, 'kg', 7, 7, 'USJR Main Gate', 'open'
    );
    raise notice 'PASS: 25 kg across 7 slots accepted';
  exception when check_violation then
    raise notice 'FAIL: a weight was refused';
  end;

  rollback;
end;
$test$;
```

Supabase's editor **swallows `RAISE NOTICE`**. If nothing shows, have them run the
two inserts as plain statements instead: the first must error with a
`check_violation` (23514), the second must succeed. Tell them to `rollback` or
delete the second row afterwards.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260715010000_add_deal_amount_and_unit.sql
git commit -m "feat: measure a deal in an amount and a unit, and refuse goods that cannot divide"
```

---

### Task 8: Verify against the running app

**Files:** none — verification only.

- [ ] **Step 1: Full suite and analyzer**

Run: `flutter test`
Expected: PASS, everything.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Drive it on the emulator**

Run the app on `emulator-5554`. A green suite does not prove the schema change
works; nothing in the Dart tests talks to Postgres.

Confirm with your own eyes:
- Posting **₱900 / 25 / kg / 7 slots** shows *"Each student pays P128.58"* and
  *"Each student gets 3.57 kg"*, and publishes.
- The deal card reads **P128.58/share** and **3.57 kg each**.
- The details screen shows the **25 kg** pill and **3.57 kg** beside the money.
- Posting **30 / pieces / 4 slots** is **refused**, with
  *"30 pieces across 4 slots leaves 7.5 each. Try 3 or 5 slots."*
- Changing that to **5 slots** lets it through, and shows *"6 pieces"* each.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: tidy up after the physical share breakdown"
```

---

## Self-Review

**Spec coverage**

| Spec requirement | Task |
|---|---|
| `DealUnit`, seven units, unit carries divisibility | 1 |
| Stored by Dart `name` (`litre`, not `L`) | 1, 3, 7 |
| `PhysicalShare` mirroring `CostSplit` | 1 |
| Single item / prime-above-ceiling refused | 1 (`canBeSplit`), 4 |
| `quantity` replaced by `amount` + `unit` | 2, 3, 7 |
| Discrete amounts must be whole | 4 (`validateAmount`) |
| Cross-field slot validation, suggests workable counts | 4 |
| CHECK constraint in Postgres | 7 |
| Migration order (view before column drop) | 7 |
| Test rice deal deleted, not migrated | 7 |
| Create form: amount + unit + live share preview | 5 |
| Details screen: real total, share beside the money | 6 |
| Deal card: share beside the price | 6 |
| Seeded mocks get real measures | 3 |
| Constraint proven in SQL | 7 |

No gaps.

**One thing I got wrong while writing this, and corrected inline:** Task 7
originally used `create or replace view` for `deal_feed`. That fails when a
column is *removed* from the select list — Postgres refuses with "cannot change
name of view column". It must be `drop view` + `create view`. Left the wrong
version visible in the task with the correction beneath it, because the engineer
is likely to reach for `create or replace` by reflex, exactly as I did.

**Type consistency:** `PhysicalShare.from({amount, unit, slots})`,
`.amountPerShare`, `.dividesEvenly`, `.canBeSplit`, `.workableSlotCounts`,
`.shareLabel`, `.totalLabel`; `DealUnit.label` / `.singularLabel` / `.continuous`
/ `.discrete`; `Deal.physicalShare`; `CreateDealViewModel.validateAmount`,
`.validateTotalSlots(value, {amount, unit})`, `.previewShare({amount, unit,
totalSlots})` — used identically everywhere they appear.

**Known soft spots, flagged rather than papered over:**
- Tasks 3, 5 and 6 modify test files whose fixtures and helpers (`pumpScreen`,
  `fillForm`, `pumpDetails`, `_deal`) I have not read end to end. Each says to
  read the file first. On the last two cards, my guessed helper names were wrong
  every time — trust the file.
- Task 2 deliberately leaves the tree not fully compiling until Task 3. That is
  the cost of changing a core model; the alternative is one enormous task.
- `lastOrNull` / `firstOrNull` in Task 4 need `package:collection`. Task 4 says to
  check `pubspec.yaml` and use plain loops rather than add a dependency for two
  calls.
