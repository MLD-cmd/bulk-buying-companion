# Split-Cost Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a bulk buy's per-share price always reconcile with its total, by splitting in whole centavos and rounding each share up so the host is never short.

**Architecture:** A pure `CostSplit` value type owns all splitting arithmetic in integer centavos. The three places that currently divide independently (`Deal.pricePerShare`, `CreateDealViewModel.previewPricePerShare`, `SplitBoardViewModel._priceValue`) all delegate to it, so there is one division in the codebase instead of three. The create-deal preview and deal details screen then surface the surplus on uneven splits instead of hiding it.

**Tech Stack:** Flutter, Dart, `flutter_test`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-14-split-cost-calculator-design.md`

**Note on existing tests:** Every current test and seeded mock deal uses figures that divide evenly (900÷5, 400÷4, 380÷4, 360÷3, 255÷3, 900÷6). No existing assertion should change. If one breaks, stop — it means a behavioural regression, not an expected update.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/models/cost_split.dart` | **New.** Pure split arithmetic in integer centavos. No I/O, no Flutter imports. |
| `test/models/cost_split_test.dart` | **New.** Unit tests for the above, including the reconciliation invariant. |
| `lib/models/deal.dart` | `pricePerShare` delegates to `CostSplit`; exposes `costSplit` so UI can read the surplus. |
| `lib/ui/split_board/create_deal_viewmodel.dart` | `previewPricePerShare` delegates; new `previewSplit`; `validateTotalPrice` gains a ₱0.01 floor. |
| `lib/ui/split_board/split_board_viewmodel.dart` | `_priceValue` drops its regex and sorts on the real number. |
| `lib/ui/split_board/create_deal_screen.dart` | `_SplitPreview` shows the surplus note on uneven splits. |
| `lib/ui/split_board/deal_details_screen.dart` | `_CostCard` shows the surplus note on uneven splits. |

---

### Task 1: The `CostSplit` value type

**Files:**
- Create: `lib/models/cost_split.dart`
- Test: `test/models/cost_split_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/models/cost_split_test.dart`:

```dart
import 'package:bulk_buying_companion/models/cost_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an even split leaves no surplus', () {
    final split = CostSplit.from(totalPrice: 900, slots: 5);

    expect(split.totalCentavos, 90000);
    expect(split.perShareCentavos, 18000);
    expect(split.collectedCentavos, 90000);
    expect(split.surplusCentavos, 0);
    expect(split.isEven, isTrue);
    expect(split.pricePerShare, 180.0);
  });

  test('an uneven split rounds the share up and surfaces the surplus', () {
    // P900 over 7 slots is 128.5714... a share. Rounded up, every student pays
    // P128.58 and the host is left holding six centavos.
    final split = CostSplit.from(totalPrice: 900, slots: 7);

    expect(split.perShareCentavos, 12858);
    expect(split.collectedCentavos, 90006);
    expect(split.surplusCentavos, 6);
    expect(split.isEven, isFalse);
    expect(split.pricePerShare, 128.58);
    expect(split.surplus, closeTo(0.06, 1e-9));
  });

  test('the shares always cover the total, by under a centavo each', () {
    // The property the whole type exists to guarantee. Asserted across the
    // real input range rather than on a couple of hand-picked cases.
    for (var centavos = 1; centavos <= 200; centavos++) {
      for (var slots = 2; slots <= 50; slots++) {
        final split = CostSplit.from(totalPrice: centavos / 100, slots: slots);

        expect(
          split.collectedCentavos,
          greaterThanOrEqualTo(split.totalCentavos),
          reason: 'the host must never be short: $centavos c over $slots slots',
        );
        expect(
          split.surplusCentavos,
          lessThan(slots),
          reason: 'overshoot must stay under a centavo per slot',
        );
      }
    }
  });

  test('the smallest usable deal still charges something', () {
    final split = CostSplit.from(totalPrice: 0.01, slots: 2);

    expect(split.perShareCentavos, 1);
    expect(split.surplusCentavos, 1);
  });

  test('rejects a price that rounds away to nothing', () {
    expect(
      () => CostSplit.from(totalPrice: 0.001, slots: 2),
      throwsArgumentError,
    );
    expect(() => CostSplit.from(totalPrice: 0, slots: 2), throwsArgumentError);
  });

  test('rejects a split with no slots to split across', () {
    expect(() => CostSplit.from(totalPrice: 900, slots: 0), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/models/cost_split_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'bulk_buying_companion/models/cost_split.dart'` (the file does not exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/models/cost_split.dart`:

```dart
/// The arithmetic of splitting one bulk buy across its slots.
///
/// Done entirely in whole centavos. A floating-point division of pesos cannot
/// promise the shares add back up to the total, and money that does not
/// reconcile is what starts arguments at pickup.
///
/// Shares round *up* to the centavo, so every student pays the same amount and
/// the host is never left covering a shortfall. The few centavos of overshoot
/// are exposed as [surplusCentavos] rather than quietly pocketed.
class CostSplit {
  const CostSplit._({required this.totalCentavos, required this.slots});

  factory CostSplit.from({required double totalPrice, required int slots}) {
    if (slots < 1) {
      throw ArgumentError.value(
        slots,
        'slots',
        'A split needs at least one slot.',
      );
    }

    final totalCentavos = (totalPrice * 100).round();
    if (totalCentavos < 1) {
      throw ArgumentError.value(
        totalPrice,
        'totalPrice',
        'A split needs a total of at least one centavo.',
      );
    }

    return CostSplit._(totalCentavos: totalCentavos, slots: slots);
  }

  final int totalCentavos;
  final int slots;

  /// Ceiling division, done on integers so there is no rounding step that can
  /// drift a share off by a centavo.
  int get perShareCentavos => (totalCentavos + slots - 1) ~/ slots;

  int get collectedCentavos => perShareCentavos * slots;

  /// What the host is left holding once every share is in. Never negative:
  /// the shares round up, so they always cover the total.
  int get surplusCentavos => collectedCentavos - totalCentavos;

  bool get isEven => surplusCentavos == 0;

  /// Peso views, for display only — derived from the integers, never used to
  /// compute one.
  double get pricePerShare => perShareCentavos / 100;
  double get collected => collectedCentavos / 100;
  double get surplus => surplusCentavos / 100;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/models/cost_split_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/cost_split.dart test/models/cost_split_test.dart
git commit -m "feat: add CostSplit, splitting a bulk buy in whole centavos"
```

---

### Task 2: Route `Deal` through `CostSplit`

**Files:**
- Modify: `lib/models/deal.dart:54` (the `pricePerShare` getter)
- Test: `test/models/cost_split_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append to `test/models/cost_split_test.dart`, and add the import
`import 'package:bulk_buying_companion/models/deal.dart';` at the top of the file:

```dart
  test('a deal that does not divide evenly rounds its share up', () {
    final deal = Deal(
      id: 'uneven',
      hubId: 'colon',
      title: '25kg Rice Sack',
      category: DealCategory.grocery,
      totalPrice: 900,
      quantity: 1,
      availableSlots: 7,
      totalSlots: 7,
      pickupLocation: 'USJR Main Gate',
      status: DealStatus.open,
    );

    expect(deal.pricePerShare, 128.58);
    expect(deal.priceLabel, 'P128.58/share');
    expect(deal.costSplit.surplusCentavos, 6);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/models/cost_split_test.dart`
Expected: FAIL — `The getter 'costSplit' isn't defined for the class 'Deal'`, and `pricePerShare` returns `128.57142857142858` rather than `128.58`.

- [ ] **Step 3: Write the implementation**

In `lib/models/deal.dart`, add the import at the top of the file:

```dart
import 'cost_split.dart';
```

Then replace the `pricePerShare` getter (currently `double get pricePerShare => totalPrice / totalSlots;`) with:

```dart
  /// Every peso figure on a deal comes from here, so the card, the details
  /// screen and the poster's preview cannot disagree with each other.
  CostSplit get costSplit =>
      CostSplit.from(totalPrice: totalPrice, slots: totalSlots);

  double get pricePerShare => costSplit.pricePerShare;
```

Leave `priceLabel` as it is — it reads `pricePerShare` and so is fixed for free.

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS. Existing deal tests use evenly-dividing figures, so none of them should change. If any existing assertion now fails, stop and investigate — that is a regression, not an expected update.

- [ ] **Step 5: Commit**

```bash
git add lib/models/deal.dart test/models/cost_split_test.dart
git commit -m "fix: round a deal's per-share price up so the shares cover the total"
```

---

### Task 3: Route the create-deal preview through `CostSplit`, and floor the price

**Files:**
- Modify: `lib/ui/split_board/create_deal_viewmodel.dart:39-46` (`validateTotalPrice`) and `:98-106` (`previewPricePerShare`)
- Test: `test/ui/split_board/create_deal_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside the existing `main()` of `test/ui/split_board/create_deal_viewmodel_test.dart`. Add
`import 'package:bulk_buying_companion/models/cost_split.dart';` to the imports if not already present:

```dart
  test('rejects a price that rounds away to nothing', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalPrice('0.001'),
      'Total price must be at least P0.01.',
    );
    expect(viewModel.validateTotalPrice('0.01'), isNull);
  });

  test('previews an uneven split with its surplus', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    final split = viewModel.previewSplit(totalPrice: '900', totalSlots: '7');

    expect(split, isNotNull);
    expect(split!.pricePerShare, 128.58);
    expect(split.surplusCentavos, 6);
    expect(split.isEven, isFalse);

    // The poster's preview and the published deal must agree.
    expect(
      viewModel.previewPricePerShare(totalPrice: '900', totalSlots: '7'),
      128.58,
    );
  });

  test('previews nothing when the price is unusable', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.previewSplit(totalPrice: '0.001', totalSlots: '7'),
      isNull,
    );
    expect(viewModel.previewSplit(totalPrice: '900', totalSlots: '0'), isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/split_board/create_deal_viewmodel_test.dart`
Expected: FAIL — `The method 'previewSplit' isn't defined`, and `validateTotalPrice('0.001')` returns `null` rather than the new message.

- [ ] **Step 3: Write the implementation**

In `lib/ui/split_board/create_deal_viewmodel.dart`, add the import:

```dart
import '../../models/cost_split.dart';
```

Replace `validateTotalPrice` with:

```dart
  String? validateTotalPrice(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter the total price.';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Total price must be a number.';
    if (parsed <= 0) return 'Total price must be more than 0.';
    // Below a centavo the split rounds away to zero and every student pays
    // nothing, which is not a deal.
    if ((parsed * 100).round() < 1) return 'Total price must be at least P0.01.';
    return null;
  }
```

Replace `previewPricePerShare` with:

```dart
  /// The split shown live under the price field, so the poster sees exactly
  /// what students will be asked to pay before publishing. Null while the
  /// inputs are unusable.
  CostSplit? previewSplit({
    required String? totalPrice,
    required String? totalSlots,
  }) {
    final price = double.tryParse((totalPrice ?? '').trim());
    final slots = int.tryParse((totalSlots ?? '').trim());
    if (price == null || slots == null) return null;
    if (slots < 1 || (price * 100).round() < 1) return null;
    return CostSplit.from(totalPrice: price, slots: slots);
  }

  double? previewPricePerShare({
    required String? totalPrice,
    required String? totalSlots,
  }) {
    return previewSplit(
      totalPrice: totalPrice,
      totalSlots: totalSlots,
    )?.pricePerShare;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/ui/split_board/create_deal_viewmodel_test.dart`
Expected: PASS, including the pre-existing `previewPricePerShare` tests (900 ÷ 5 = 180, and nulls for empty/zero slots).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/split_board/create_deal_viewmodel.dart test/ui/split_board/create_deal_viewmodel_test.dart
git commit -m "fix: preview the real split when publishing, and floor the price at P0.01"
```

---

### Task 4: Sort the split board on the real number, not a parsed label

**Files:**
- Modify: `lib/ui/split_board/split_board_viewmodel.dart:150-154` (`_priceValue`)
- Test: `test/ui/split_board/split_board_viewmodel_test.dart`

`_priceValue` currently regex-parses the *formatted display string* (`"P128.58/share"`) back into a number to sort on. That number → text → number round-trip breaks the moment the label format changes. Now that a real numeric per-share exists, sort on it.

- [ ] **Step 1: Write the failing test**

Append inside the existing `main()` of `test/ui/split_board/split_board_viewmodel_test.dart`:

```dart
  test('sorts by price on deals whose shares do not divide evenly', () async {
    // P100 over 3 slots is P33.34 a share; P100 over 4 is P25.00. Sorting must
    // order them on those numbers, not on the text of their labels.
    final viewModel = SplitBoardViewModel(
      dealRepository: _StubDealRepository([
        _deal(id: 'thirds', totalPrice: 100, totalSlots: 3),
        _deal(id: 'quarters', totalPrice: 100, totalSlots: 4),
      ]),
      hubId: 'colon',
    );

    await pumpEventQueue();
    viewModel.setSortOption(DealSortOption.price);

    expect(viewModel.visibleDeals.map((deal) => deal.id), [
      'quarters',
      'thirds',
    ]);
  });
```

If `_StubDealRepository` and a `_deal` helper do not already exist in this test file under those names, reuse whatever equivalent stub and deal-builder the file already defines — read the file first and match its existing helpers rather than adding duplicates. Likewise confirm the real names of the sort setter and the visible-deals getter (`setSortOption` / `visibleDeals`) against the file and use those.

- [ ] **Step 2: Run the test to verify it fails or passes for the wrong reason**

Run: `flutter test test/ui/split_board/split_board_viewmodel_test.dart`
Expected: the new test PASSES even before the change, because the regex happens to parse these particular labels correctly. That is fine and expected — the test pins the *behaviour* so the refactor in Step 3 is provably safe. Its value is as a regression guard, not as a red test.

- [ ] **Step 3: Write the implementation**

In `lib/ui/split_board/split_board_viewmodel.dart`, replace `_priceValue` entirely:

```dart
  double _priceValue(Deal deal) => deal.pricePerShare;
```

Delete the now-unused `RegExp` line with it. If `dart:core`'s `RegExp` was the only reason for an import in this file, remove that too (it is not — `RegExp` needs no import — so no import change is expected here).

- [ ] **Step 4: Run the tests to verify they still pass**

Run: `flutter test test/ui/split_board/split_board_viewmodel_test.dart`
Expected: PASS, including the pre-existing price-sort tests (4800 → P1,200/share, 380 → P95/share, 600 → P150/share).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/split_board/split_board_viewmodel.dart test/ui/split_board/split_board_viewmodel_test.dart
git commit -m "refactor: sort deals by price on the number, not a regex over the label"
```

---

### Task 5: Show the surplus in the create-deal preview

**Files:**
- Modify: `lib/ui/split_board/create_deal_screen.dart:168-173` (the `_SplitPreview` call site) and `:326-357` (the `_SplitPreview` widget)
- Test: `test/ui/split_board/create_deal_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside the existing `main()` of `test/ui/split_board/create_deal_screen_test.dart`. Match the file's existing pump/setup helpers — read it first and reuse how it already builds the screen and enters text:

```dart
  testWidgets('states the surplus when the split is uneven', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('deal-total-price-field')), '900');
    await tester.enterText(find.byKey(const Key('deal-total-slots-field')), '7');
    await tester.pump();

    expect(find.text('Each student pays P128.58'), findsOneWidget);
    expect(
      find.byKey(const Key('deal-split-surplus')),
      findsOneWidget,
      reason: 'an uneven split must say so rather than hide the centavos',
    );
  });

  testWidgets('says nothing about surplus when the split is even', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('deal-total-price-field')), '900');
    await tester.enterText(find.byKey(const Key('deal-total-slots-field')), '5');
    await tester.pump();

    expect(find.text('Each student pays P180'), findsOneWidget);
    expect(find.byKey(const Key('deal-split-surplus')), findsNothing);
  });
```

Confirm the price field's key against the screen (the slots field is `deal-total-slots-field`; use whatever the price field's actual key is — check `create_deal_screen.dart`). If the price field has no key, add `key: const Key('deal-total-price-field')` to it as part of Step 3.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/split_board/create_deal_screen_test.dart`
Expected: FAIL — the uneven test finds no `deal-split-surplus` widget. The even test should already pass (it pins existing behaviour).

- [ ] **Step 3: Write the implementation**

In `lib/ui/split_board/create_deal_screen.dart`, add the import:

```dart
import '../../models/cost_split.dart';
```

Change the `_SplitPreview` call site (currently passing `pricePerShare:`) to pass the whole split:

```dart
                    _SplitPreview(
                      split: viewModel.previewSplit(
                        totalPrice: _totalPriceController.text,
                        totalSlots: _totalSlotsController.text,
                      ),
                    ),
```

Replace the `_SplitPreview` widget with:

```dart
/// The whole point of the app: what one student actually pays.
class _SplitPreview extends StatelessWidget {
  const _SplitPreview({required this.split});

  final CostSplit? split;

  @override
  Widget build(BuildContext context) {
    final split = this.split;
    if (split == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Each student pays ${formatPeso(split.pricePerShare)}',
                key: const Key('deal-split-preview'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          // An uneven split is stated, not hidden: the shares round up, so they
          // collect a few centavos more than the item costs.
          if (!split.isEven) ...[
            const SizedBox(height: 4),
            Text(
              '${split.slots} shares collect ${formatPeso(split.collected)} — '
              '${formatPeso(split.surplus)} over. The difference stays with you.',
              key: const Key('deal-split-surplus'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/ui/split_board/create_deal_screen_test.dart`
Expected: PASS, including the pre-existing `Each student pays P180` assertion.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/split_board/create_deal_screen.dart test/ui/split_board/create_deal_screen_test.dart
git commit -m "feat: state the surplus in the create-deal split preview"
```

---

### Task 6: Show the surplus on the deal details screen

**Files:**
- Modify: `lib/ui/split_board/deal_details_screen.dart:128-190` (the `_CostCard` widget)
- Test: `test/ui/split_board/deal_details_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside the existing `main()` of `test/ui/split_board/deal_details_screen_test.dart`. Reuse the file's existing helper for building the screen with a given deal — read it first and match it:

```dart
  testWidgets('states the surplus when the deal does not divide evenly', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        _deal(totalPrice: 900, totalSlots: 7, availableSlots: 7),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-cost-per-slot')), findsOneWidget);
    expect(find.text('P128.58'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsOneWidget);
  });

  testWidgets('says nothing about surplus on an even deal', (tester) async {
    await tester.pumpWidget(
      _screen(_deal(totalPrice: 900, totalSlots: 5, availableSlots: 5)),
    );
    await tester.pumpAndSettle();

    expect(find.text('P180'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsNothing);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/split_board/deal_details_screen_test.dart`
Expected: FAIL — no `detail-split-surplus` widget exists. The even test should already pass.

- [ ] **Step 3: Write the implementation**

In `lib/ui/split_board/deal_details_screen.dart`, restructure `_CostCard` so the existing `Row` sits inside a `Column`, with the surplus note beneath it. Replace the widget's `build` with:

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = deal.costSplit;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR SHARE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPeso(deal.pricePerShare),
                      key: const Key('detail-cost-per-slot'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total ${formatPeso(deal.totalPrice)}',
                    key: const Key('detail-total-price'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'split ${deal.totalSlots} ways',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // The share rounds up, so the shares collect slightly more than the
          // item cost. Say so, rather than leaving two figures that do not
          // reconcile sitting next to each other.
          if (!split.isEven) ...[
            const SizedBox(height: 10),
            Text(
              'Shares round up, so the ${split.slots} of you pay '
              '${formatPeso(split.collected)} in total — '
              '${formatPeso(split.surplus)} over the item cost, kept by the host.',
              key: const Key('detail-split-surplus'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
```

The trailing `Column` inside the `Row` (`Total …` / `split N ways`) may extend past line 190 in the current file; replace the whole `build` method, not a fragment of it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/ui/split_board/deal_details_screen_test.dart`
Expected: PASS, including the pre-existing `P180` and `detail-total-price` assertions.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/split_board/deal_details_screen.dart test/ui/split_board/deal_details_screen_test.dart
git commit -m "feat: state the surplus on the deal details cost card"
```

---

### Task 7: Verify the whole suite and the analyzer

**Files:** none — verification only.

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS, all tests. Nothing that passed before this plan should fail now.

- [ ] **Step 2: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`. In particular there should be no unused-import or unused-element warnings left behind by the `_priceValue` and `_SplitPreview` rewrites.

- [ ] **Step 3: Drive the app and look at a real uneven deal**

Run the app, publish a deal for ₱900 across 7 slots, and confirm with your own eyes:
- the create-deal preview reads `Each student pays P128.58` with the surplus line beneath it,
- the deal card on the split board reads `P128.58/share`,
- the details screen shows `P128.58` against `Total P900` with the surplus note.

A green suite is not the same as a correct screen. Look at it.

- [ ] **Step 4: Commit any fixes**

If the analyzer or the app run turned up anything, fix it and commit:

```bash
git add -A
git commit -m "fix: tidy up after the split-cost calculator"
```

---

## Self-Review

**Spec coverage**

| Spec requirement | Task |
|---|---|
| Round shares up; host keeps surplus | 1 |
| Integer-centavo representation | 1 |
| `CostSplit` value type with the named API | 1 |
| `Deal.pricePerShare` delegates | 2 |
| `previewPricePerShare` delegates | 3 |
| ₱0.01 price floor | 3 |
| `_priceValue` drops the regex | 4 |
| Calculation summary on uneven splits | 5, 6 |
| Even split: UI unchanged | 5, 6 (both have an explicit "says nothing" test) |
| Test: even, uneven, invariant, bounds, min price | 1 |
| Slot bounds (2–50) unchanged | Not a task — already enforced by `validateTotalSlots`; the invariant test in Task 1 covers slots 2–50. |

No gaps.

**Type consistency:** `CostSplit.from({totalPrice, slots})`, `.totalCentavos`, `.perShareCentavos`, `.collectedCentavos`, `.surplusCentavos`, `.isEven`, `.pricePerShare`, `.collected`, `.surplus`, `Deal.costSplit`, `CreateDealViewModel.previewSplit` — used identically in every task that references them. Widget keys `deal-split-surplus` and `detail-split-surplus` are distinct and each used in exactly one screen and its test.

**Known soft spots, flagged rather than papered over:** Tasks 4, 5 and 6 append to existing test files whose private helpers (`_screen`, `_deal`, `_StubDealRepository`) I have not read in full. Each of those steps says to read the file first and match its existing helpers. That is deliberate — inventing helper names that do not exist would be worse than saying so.
