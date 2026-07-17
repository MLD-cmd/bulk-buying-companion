# Frontend Polish and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the verified hub/profile layout defects, prevent discovery and board content from stretching on wide displays, and reduce measured scrolling raster cost without changing the app's routes, fields, data, or supported features.

**Architecture:** Keep the existing Provider view models and repository contracts intact. Apply responsive decisions inside the current presentation widgets, virtualize feed rows with slivers, and isolate the long form's visual sections into separate repaint layers. Validate the result with focused widget tests, the full Flutter test suite, analyzer output, and before/after profile-mode timelines from the Pixel 8 emulator.

**Tech Stack:** Flutter 3, Material 3, Dart, Provider, flutter_test, Android Pixel 8 API 35 profile build.

---

### Task 1: Compact hub actions and remove redundant profile navigation

**Files:**
- Modify: `lib/ui/hub/widgets/hub_card.dart`
- Modify: `lib/ui/profile/profile_screen.dart`
- Modify: `test/ui/frontend_responsive_test.dart`
- Modify: `test/ui/profile/profile_screen_test.dart`

- [x] **Step 1: Add failing behavior tests**

Add a normal Pixel-width hub-card test that requires the action to remain in the summary row with a 48 dp accessible hit target, while retaining the existing 320 px / 200% text fallback. Add a no-hub profile test that verifies the empty card explains the state without rendering `Find a hub`.

```dart
expect(tester.getSize(find.byKey(const Key('hub-join-button'))).height, 48);
expect(
  tester.getCenter(find.byKey(const Key('hub-join-button'))).dy,
  closeTo(tester.getCenter(find.byType(AppIconContainer)).dy, 24),
);
expect(find.text('Find a hub'), findsNothing);
```

- [x] **Step 2: Verify the tests fail**

Run: `flutter test test/ui/frontend_responsive_test.dart test/ui/profile/profile_screen_test.dart`

Expected: FAIL because a normal 411 dp phone currently stacks the hub action below the summary and the no-hub profile card still renders the redundant destination.

- [x] **Step 3: Implement compact contextual actions**

Change the hub card breakpoint so only genuinely constrained widths or enlarged text stack the action. Apply a local 48 dp minimum and compact horizontal padding to Join/Switch/Confirm/Cancel controls; do not reduce the global form-button theme.

```dart
final stackAction = constraints.maxWidth < 300 || textScale > 1.3;
final actionStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  ),
);
```

- [x] **Step 4: Remove the redundant no-hub action**

Keep the current-hub empty card's icon and explanatory copy, but remove the `TextButton.icon` that pops back to the already visible discovery route.

- [x] **Step 5: Format and rerun targeted tests**

Run: `dart format lib/ui/hub/widgets/hub_card.dart lib/ui/profile/profile_screen.dart test/ui/frontend_responsive_test.dart test/ui/profile/profile_screen_test.dart && flutter test test/ui/frontend_responsive_test.dart test/ui/profile/profile_screen_test.dart`

Expected: PASS.

### Task 2: Bound responsive discovery and board content

**Files:**
- Modify: `lib/ui/hub/join_hub_screen.dart`
- Modify: `lib/ui/split_board/split_board_screen.dart`
- Modify: `test/ui/hub/hub_screens_test.dart`
- Modify: `test/ui/split_board/split_board_screen_test.dart`

- [x] **Step 1: Add failing wide-layout tests**

Pump each screen at 1200 logical pixels and assert that discovery controls/list rows do not exceed 720 dp and board controls/cards do not exceed 760 dp.

```dart
expect(tester.getSize(find.byKey(const Key('hub-search-field'))).width, lessThanOrEqualTo(720));
expect(tester.getSize(find.byKey(const Key('board-search-field'))).width, lessThanOrEqualTo(760));
```

- [x] **Step 2: Verify the wide-layout tests fail**

Run: `flutter test test/ui/hub/hub_screens_test.dart test/ui/split_board/split_board_screen_test.dart`

Expected: FAIL because discovery and feed content currently consume the entire available width.

- [x] **Step 3: Center a shared content column per screen**

Wrap the discovery header controls and list rows in centered constraints capped at 720 dp. Cap the Split Board feed at 760 dp while keeping phone gutters at 20 dp and preserving pull-to-refresh, FAB clearance, safe areas, and existing state handling.

- [x] **Step 4: Format and rerun responsive tests**

Run: `dart format lib/ui/hub/join_hub_screen.dart lib/ui/split_board/split_board_screen.dart test/ui/hub/hub_screens_test.dart test/ui/split_board/split_board_screen_test.dart && flutter test test/ui/hub/hub_screens_test.dart test/ui/split_board/split_board_screen_test.dart`

Expected: PASS with no overflow at narrow widths or 200% text scale.

### Task 3: Virtualize the board and isolate long-form raster work

**Files:**
- Modify: `lib/ui/split_board/split_board_screen.dart`
- Modify: `lib/ui/split_board/create_deal_screen.dart`
- Modify: `test/ui/split_board/split_board_screen_test.dart`
- Modify: `test/ui/split_board/create_deal_screen_test.dart`

- [x] **Step 1: Add a failing lazy-feed test**

Provide enough deals to exceed the viewport and assert the last keyed row is not built until the list scrolls to it.

```dart
expect(find.byKey(const Key('deal-card-deal-39')), findsNothing);
await tester.scrollUntilVisible(
  find.byKey(const Key('deal-card-deal-39')),
  600,
  scrollable: find.byType(Scrollable).first,
);
expect(find.byKey(const Key('deal-card-deal-39')), findsOneWidget);
```

- [x] **Step 2: Verify the lazy-feed test fails**

Run: `flutter test test/ui/split_board/split_board_screen_test.dart`

Expected: FAIL because the current `ListView(children:)` eagerly creates every deal widget.

- [x] **Step 3: Replace eager feed rows with slivers**

Use `CustomScrollView`, a `SliverToBoxAdapter` for the filter bar, and `SliverList.builder` for deal rows. Keep the no-match state in the same scroll view and preserve the current navigation callback and 100 dp FAB clearance.

- [x] **Step 4: Add repaint boundaries to form sections**

Wrap Product, Split, Pickup, and Review `AppFormSection` instances in `RepaintBoundary` widgets. Keep the existing `SingleChildScrollView` and `Form` registration behavior so validation remains complete even for fields currently offscreen.

```dart
RepaintBoundary(
  child: AppFormSection(
    title: 'Split',
    description: 'Set the total purchase and what each member receives.',
    icon: Icons.call_split_outlined,
    children: splitFields,
  ),
)
```

- [x] **Step 5: Run feature regressions**

Run: `dart format lib/ui/split_board test/ui/split_board && flutter test test/ui/split_board`

Expected: PASS with unchanged create, search, filter, navigation, lifecycle, and submit behavior.

### Task 4: Verify behavior, accessibility, and profile performance

**Files:**
- Verify: all changed Flutter and test files

- [x] **Step 1: Run analyzer and the complete test suite**

Run: `flutter analyze && flutter test`

Expected: analyzer reports no issues and every test passes.

- [x] **Step 2: Rebuild the Pixel 8 profile app**

Run: `flutter run --profile -d emulator-5554`

Expected: the app launches with Impeller on the configured Pixel 8 API 35 emulator.

- [x] **Step 3: Re-navigate the changed flows**

Inspect hub discovery, Profile, Split Board, deal details, and Post a deal directly in the emulator. Confirm compact hub actions, no redundant no-hub action in widget coverage, centered wide-layout behavior, preserved back navigation, no overflows, and complete form scrolling.

- [x] **Step 4: Repeat the timeline measurement**

Clear `getVMTimeline`, exercise the same keyboard-free form scroll, and compare `Frame` and `GPURasterizer::Draw` durations with the baseline: hub list 0/59 over 16.7 ms; form scroll 75/208 raster frames over 16.7 ms with a 38.9 ms maximum.

Expected: UI frames remain under budget and form raster misses/max duration materially improve without a regression in the hub list.

- [x] **Step 5: Prepare the conventional commit for approval**

Stage only the plan, Flutter UI files, and tests. Preserve the user's untracked `AGENTS.md`. Create one natural Conventional Commit with a detailed body, then show the exact title and description before any push or merge.
