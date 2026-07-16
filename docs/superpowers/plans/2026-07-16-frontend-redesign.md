# Frontend Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved teal campus co-op design system to every existing Flutter screen while preserving the current data, validation, lifecycle, and navigation contracts.

**Architecture:** Keep Provider view models and repository interfaces unchanged. Introduce a theme-owned visual foundation plus a small set of focused shared presentation widgets, then migrate each feature screen to those primitives and cover the resulting layouts with widget tests at narrow and enlarged-text viewports.

**Tech Stack:** Flutter 3, Material 3, Dart, Provider, flutter_test, bundled Manrope and Outfit font assets.

---

### Task 1: Establish the frontend design foundation

**Files:**
- Modify: `pubspec.yaml`
- Add: `assets/fonts/Manrope-VariableFont_wght.ttf`
- Add: `assets/fonts/Outfit-VariableFont_wght.ttf`
- Modify: `lib/ui/shared/app_theme.dart`
- Create: `lib/ui/shared/app_banner.dart`
- Create: `lib/ui/shared/app_form_section.dart`
- Create: `lib/ui/shared/app_icon_container.dart`
- Create: `lib/ui/shared/app_message_state.dart`
- Test: `test/ui/shared/app_theme_test.dart`
- Test: `test/ui/shared/app_components_test.dart`

- [ ] **Step 1: Write failing theme and component tests**

Add tests that assert the light theme uses `Color(0xFF0F766E)`, the dark theme keeps a teal primary, controls meet the 44-pixel minimum, form fields use a 12-pixel radius, `AppBanner` exposes a live region, and `AppMessageState` renders its title, message, icon, and optional retry action.

```dart
test('light theme exposes the approved semantic palette', () {
  final theme = AppTheme.light();
  expect(theme.colorScheme.primary, const Color(0xFF0F766E));
  expect(theme.scaffoldBackgroundColor, const Color(0xFFF6FAF9));
  expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
  expect(theme.textTheme.headlineSmall?.fontFamily, 'Outfit');
});
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run: `flutter test test/ui/shared/app_theme_test.dart test/ui/shared/app_components_test.dart`

Expected: FAIL because the approved theme values and shared widgets do not exist yet.

- [ ] **Step 3: Register bundled fonts**

Add the font families under `flutter.fonts` while preserving the existing `.env` asset.

```yaml
  fonts:
    - family: Manrope
      fonts:
        - asset: assets/fonts/Manrope-VariableFont_wght.ttf
    - family: Outfit
      fonts:
        - asset: assets/fonts/Outfit-VariableFont_wght.ttf
```

- [ ] **Step 4: Replace the one-off theme with semantic theme ownership**

Build light and dark `ColorScheme` values around teal, configure Manrope for body text and Outfit for headings, and centralize app bars, buttons, fields, chips, cards, dividers, progress, snack bars, and dialogs.

```dart
class AppTheme {
  AppTheme._();

  static const primary = Color(0xFF0F766E);
  static const success = Color(0xFF166534);
  static const successContainer = Color(0xFFE7F6EC);
  static const warning = Color(0xFF8A4B08);
  static const warningContainer = Color(0xFFFFF3D6);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: const Color(0xFFFFFFFF),
    ),
    const Color(0xFFF6FAF9),
  );
}
```

- [ ] **Step 5: Add the focused shared presentation widgets**

Implement `AppBanner`, `AppFormSection`, `AppIconContainer`, and `AppMessageState`. Each widget owns only presentation and semantics; no repository or view-model dependency is permitted.

```dart
Semantics(
  container: true,
  liveRegion: true,
  child: DecoratedBox(
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [Icon(icon), Expanded(child: Text(message))]),
  ),
)
```

- [ ] **Step 6: Format and run the foundation tests**

Run: `dart format lib/ui/shared test/ui/shared && flutter test test/ui/shared`

Expected: PASS.

- [ ] **Step 7: Commit the foundation**

```bash
git add pubspec.yaml assets/fonts lib/ui/shared test/ui/shared
git commit -m "feat: establish the accessible frontend design system" -m "Introduce the approved teal semantic palette, bundled Manrope and Outfit typography, consistent Material 3 component themes, and reusable presentation primitives for banners, form sections, icon containers, and message states. Add focused widget coverage for color roles, typography, touch targets, live-region semantics, and reusable empty or error states."
```

### Task 2: Refine authentication without changing account behavior

**Files:**
- Modify: `lib/ui/auth/auth_screen.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Add authentication layout assertions**

Extend the existing login and registration tests to assert the basket mark, mode control, in-field labels, primary action, error/notice banner semantics, and no overflow at 320 logical pixels with 200% text scaling.

```dart
tester.view.physicalSize = const Size(320, 900);
tester.view.devicePixelRatio = 1;
tester.platformDispatcher.textScaleFactorTestValue = 2;
expect(tester.takeException(), isNull);
```

- [ ] **Step 2: Run the targeted authentication tests and verify the new layout check fails**

Run: `flutter test test/widget_test.dart --plain-name "app opens on the login screen"`

Expected: FAIL on the new structural or narrow-layout assertion before the screen is migrated.

- [ ] **Step 3: Migrate the authentication screen**

Keep the existing controllers, validators, view-model methods, field keys, and submit flow. Replace local colors and borders with theme values, use the shared banner for error and notice states, constrain the form to 440 pixels, and keep the visual hierarchy to brand, title, mode selector, fields, and one submit action.

```dart
return SingleChildScrollView(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  child: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Form(key: _formKey, child: Column(children: fields)),
    ),
  ),
);
```

- [ ] **Step 4: Run the authentication regression tests**

Run: `dart format lib/ui/auth/auth_screen.dart test/widget_test.dart && flutter test test/widget_test.dart test/ui/auth/auth_viewmodel_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit authentication**

```bash
git add lib/ui/auth/auth_screen.dart test/widget_test.dart
git commit -m "feat: refine the authentication experience" -m "Apply the shared typography, spacing, fields, segmented mode control, and accessible message banners to login and registration while preserving all existing validation, password visibility, confirmation notices, submission states, and account flows. Add narrow-width and enlarged-text regression coverage for the starting screen."
```

### Task 3: Improve hub discovery, registration, and profile

**Files:**
- Modify: `lib/ui/hub/join_hub_screen.dart`
- Modify: `lib/ui/hub/widgets/hub_card.dart`
- Modify: `lib/ui/hub/create_hub_screen.dart`
- Modify: `lib/ui/profile/profile_screen.dart`
- Create: `test/ui/hub/hub_screens_test.dart`
- Create: `test/ui/profile/profile_screen_test.dart`

- [ ] **Step 1: Write hub and profile widget tests**

Cover the search prompt inside the hub field, centered full-width location action, editable latitude and longitude fields, current-hub state, join/switch actions, profile initials, current hub, logout, and absence of unsupported profile destinations.

```dart
expect(
  tester.widget<TextField>(find.byKey(const Key('hub-search-field')))
      .decoration?.hintText,
  'Search hubs, buildings, areas…',
);
expect(find.text('Edit profile'), findsNothing);
expect(find.text('Notifications'), findsNothing);
```

- [ ] **Step 2: Run the new screen tests and verify they fail**

Run: `flutter test test/ui/hub/hub_screens_test.dart test/ui/profile/profile_screen_test.dart`

Expected: FAIL because the new keys, component structure, and responsive assertions are absent.

- [ ] **Step 3: Migrate hub discovery and cards**

Put the search instruction inside one field, retain the 2 km nearby capability from `kNearbyRadiusMeters`, move register/profile destinations into labeled accessible app-bar actions where width permits, and restyle current hub, hub rows, membership state, join, switch, loading, location failure, and empty states using the shared theme.

```dart
TextField(
  key: const Key('hub-search-field'),
  decoration: const InputDecoration(
    hintText: 'Search hubs, buildings, areas…',
    prefixIcon: Icon(Icons.search_outlined),
  ),
)
```

- [ ] **Step 4: Migrate hub registration**

Preserve name, hub type, location lookup, coordinates, validation, submission, and returned `Hub`. Group the fields with `AppFormSection`, use shared banners, and center the icon/label within the full-width location button.

```dart
OutlinedButton.icon(
  key: const Key('hub-use-location-button'),
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    alignment: Alignment.center,
  ),
  onPressed: isLocating ? null : onPressed,
  icon: const Icon(Icons.my_location_outlined),
  label: const Text('Use my current location'),
)
```

- [ ] **Step 5: Migrate profile**

Keep initials, display name, email, current hub/no-hub state, error, and logout only. Replace hard-coded brown/green values with semantic theme colors and retain the existing sign-out behavior.

- [ ] **Step 6: Run hub and profile regression coverage**

Run: `dart format lib/ui/hub lib/ui/profile test/ui/hub test/ui/profile && flutter test test/ui/hub test/ui/profile test/widget_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit hub and profile work**

```bash
git add lib/ui/hub lib/ui/profile test/ui/hub test/ui/profile test/widget_test.dart
git commit -m "feat: improve hub discovery and profile screens" -m "Unify hub discovery, registration, membership states, and profile presentation around the approved component system. Keep search guidance inside the field, center the current-location action, retain editable coordinates and existing join or switch behavior, and remove hard-coded visual drift without introducing unsupported profile features. Add widget coverage for responsive layouts, supported actions, and empty or error states."
```

### Task 4: Streamline Split Board browsing

**Files:**
- Modify: `lib/ui/split_board/split_board_screen.dart`
- Modify: `lib/ui/split_board/widgets/deal_card.dart`
- Modify: `test/ui/split_board/split_board_screen_test.dart`
- Modify: `test/ui/split_board/deal_card_test.dart`

- [ ] **Step 1: Add board hierarchy and filter tests**

Assert that the search instruction is an in-field hint, the hub context stays in the app bar, narrow layouts expose one labeled Filters action, active category/status filters stay removable, and each deal card prioritizes price per share, physical share, slots, deadline, and text status.

```dart
expect(
  tester.widget<TextField>(find.byKey(const Key('board-search-field')))
      .decoration?.hintText,
  'Search by product name',
);
expect(find.widgetWithText(OutlinedButton, 'Filters'), findsOneWidget);
```

- [ ] **Step 2: Run board tests and verify the new assertions fail**

Run: `flutter test test/ui/split_board/split_board_screen_test.dart test/ui/split_board/deal_card_test.dart`

Expected: FAIL because the existing filter panel is always expanded and the search uses a label.

- [ ] **Step 3: Implement the responsive board filter bar**

Keep all `SplitBoardViewModel` filter and sort methods. Render search plus a labeled Filters button on narrow screens, reveal the existing dropdowns in a modal bottom sheet, and show active choices as removable chips. On wider layouts, show the controls inline.

```dart
FilledButton.tonalIcon(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FilterSheet(viewModel: viewModel),
  ),
  icon: const Icon(Icons.tune_outlined),
  label: const Text('Filters'),
)
```

- [ ] **Step 4: Restyle deal cards and feed states**

Use a circular category icon container, one subtle divider-based row surface, semantic status badges, and a strict content order of title, price/share, physical share, slots/deadline/status. Keep the existing card key, tap navigation, refresh, floating action, and lifecycle updates.

- [ ] **Step 5: Run board regression tests**

Run: `dart format lib/ui/split_board/split_board_screen.dart lib/ui/split_board/widgets/deal_card.dart test/ui/split_board && flutter test test/ui/split_board/split_board_screen_test.dart test/ui/split_board/deal_card_test.dart test/ui/split_board/split_board_viewmodel_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit board browsing**

```bash
git add lib/ui/split_board/split_board_screen.dart lib/ui/split_board/widgets/deal_card.dart test/ui/split_board
git commit -m "feat: streamline Split Board browsing" -m "Rework the deal feed around a single in-field search control, responsive filter access, removable active filters, and cleaner deal rows that prioritize per-share cost and physical allocation. Preserve category, status, sort, refresh, navigation, posting, and lifecycle updates while improving narrow-screen scanning and semantic status clarity."
```

### Task 5: Organize the deal creation experience

**Files:**
- Modify: `lib/ui/split_board/create_deal_screen.dart`
- Modify: `test/ui/split_board/create_deal_screen_test.dart`

- [ ] **Step 1: Add creation-section and state-retention tests**

Cover the Product, Split, and Pickup headings, existing inputs, cost/physical previews, uneven-split explanation, draft review, disabled submit state, validation, and retained values after scrolling between sections.

```dart
expect(find.text('Product'), findsOneWidget);
expect(find.text('Split'), findsOneWidget);
expect(find.text('Pickup'), findsOneWidget);
expect(find.byKey(const Key('deal-total-price-field')), findsOneWidget);
expect(find.byKey(const Key('deal-pickup-location-field')), findsOneWidget);
```

- [ ] **Step 2: Run the creation tests and verify the section assertions fail**

Run: `flutter test test/ui/split_board/create_deal_screen_test.dart`

Expected: FAIL because the existing form does not use the approved section hierarchy.

- [ ] **Step 3: Recompose the existing form into visual sections**

Keep the single route, state object, controllers, `CreateDealViewModel`, keys, validators, cost split, physical share, deadline picker, and submit result. Use `AppFormSection` for Product, Split, Pickup, and Review with no new domain state or route.

```dart
AppFormSection(
  title: 'Split',
  description: 'Set the total purchase and what every member receives.',
  icon: Icons.pie_chart_outline,
  children: [priceField, amountField, unitField, shareField, splitPreview],
)
```

- [ ] **Step 4: Run creation and view-model regression coverage**

Run: `dart format lib/ui/split_board/create_deal_screen.dart test/ui/split_board/create_deal_screen_test.dart && flutter test test/ui/split_board/create_deal_screen_test.dart test/ui/split_board/create_deal_viewmodel_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit deal creation**

```bash
git add lib/ui/split_board/create_deal_screen.dart test/ui/split_board/create_deal_screen_test.dart
git commit -m "feat: organize the deal creation flow" -m "Recompose the existing creation form into clear Product, Split, Pickup, and Review sections while retaining one route, one state owner, every current field, validation rule, monetary split preview, physical allocation preview, deadline control, and submission contract. Add coverage that protects section visibility, draft retention, error presentation, and publish behavior."
```

### Task 6: Clarify deal details and lifecycle actions

**Files:**
- Modify: `lib/ui/split_board/deal_details_screen.dart`
- Modify: `test/ui/split_board/deal_details_screen_test.dart`

- [ ] **Step 1: Add details hierarchy and action tests**

Extend participant and host scenarios to assert the title/category/status header, per-share and physical-share emphasis, slot progress semantics, pickup and deadline metadata, participants, organizer, bottom action reachability, and destructive action styling.

```dart
expect(find.byKey(const Key('detail-cost-per-slot')), findsOneWidget);
expect(find.byKey(const Key('detail-physical-share')), findsOneWidget);
expect(
  tester.widget<Semantics>(find.byKey(const Key('detail-slot-progress')))
      .properties.label,
  contains('slots'),
);
```

- [ ] **Step 2: Run details tests and verify the new hierarchy assertions fail**

Run: `flutter test test/ui/split_board/deal_details_screen_test.dart`

Expected: FAIL because the approved semantic keys and persistent action layout are not present.

- [ ] **Step 3: Recompose details without changing lifecycle behavior**

Keep every `DealDetailsViewModel` command and authorization check. Reorder the existing content into overview, split, pickup, participants, organizer, and host/participant controls; use the shared banner and semantic status styling; put only the currently relevant primary action in a `SafeArea` bottom action container.

```dart
bottomNavigationBar: DealActionBar(
  child: _buildPrimaryAction(context, viewModel),
),
```

- [ ] **Step 4: Verify participant and host lifecycle coverage**

Run: `dart format lib/ui/split_board/deal_details_screen.dart test/ui/split_board/deal_details_screen_test.dart && flutter test test/ui/split_board/deal_details_screen_test.dart test/ui/split_board/deal_details_viewmodel_test.dart test/models/deal_status_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit deal details**

```bash
git add lib/ui/split_board/deal_details_screen.dart test/ui/split_board/deal_details_screen_test.dart
git commit -m "feat: clarify deal details and lifecycle actions" -m "Reorder deal details around status, per-share value, physical allocation, slot progress, pickup, participants, and organizer context, with the relevant participant or host action kept reachable in a safe bottom action area. Preserve reservation, payment, purchase, collection, cancellation, refund warning, authorization, and returned-deal behavior while making destructive controls visually distinct."
```

### Task 7: Complete responsive and accessibility regression coverage

**Files:**
- Create: `test/ui/frontend_responsive_test.dart`
- Modify: `test/widget_test.dart`
- Modify: `README.md`

- [ ] **Step 1: Add representative viewport tests**

Pump authentication, hub discovery, hub registration, board, creation, details, and profile at 320 and 390 logical pixels plus a tablet width. Repeat the core path at 200% text scaling, assert no overflow exception, and verify tooltips or semantic labels for compact icon actions.

```dart
Future<void> expectNoLayoutException(WidgetTester tester) async {
  await tester.pump();
  expect(tester.takeException(), isNull);
}
```

- [ ] **Step 2: Run the responsive suite and fix presentation-only failures**

Run: `flutter test test/ui/frontend_responsive_test.dart`

Expected: PASS after reflowing any unsafe row into a `Wrap`, `Flexible`, or narrow-layout column. Do not change view-model or repository behavior to satisfy layout tests.

- [ ] **Step 3: Document the frontend system**

Add a concise README section listing the semantic theme source, shared presentation widgets, supported viewports, bundled fonts, and the command used for frontend regression coverage.

- [ ] **Step 4: Run the complete verification suite**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`

Expected: formatter exits 0, analyzer reports no issues, and every test passes.

- [ ] **Step 5: Commit final regression coverage and documentation**

```bash
git add test/ui/frontend_responsive_test.dart test/widget_test.dart README.md
git commit -m "test: cover responsive and accessible frontend states" -m "Add representative phone, tablet, and 200 percent text-scale coverage across the existing product flow, including overflow protection, semantic labels, touch-target expectations, and supported empty or error states. Document the shared frontend system and the verification command without changing repositories, database contracts, or business logic."
```

### Task 8: Final visual and source review

**Files:**
- Review: `lib/ui/**`
- Review: `test/ui/**`
- Review: `docs/superpowers/specs/2026-07-16-frontend-redesign-design.md`

- [ ] **Step 1: Scan for visual drift and unsupported features**

Run: `rg -n "B8791F|DCEFE3|styleFrom|Edit profile|Notifications|My deals|Verified student" lib/ui`

Expected: no legacy brown palette, unsupported destinations, or avoidable local button styling remains.

- [ ] **Step 2: Check scope against the approved specification**

Confirm every existing screen uses shared theme roles, search instructions are inside fields, the location action is centered, the current coordinate fields remain, lifecycle actions are unchanged, and no repository, model, Supabase migration, or database file is modified.

- [ ] **Step 3: Inspect the branch diff and commit history**

Run: `git diff --check develop...HEAD && git diff --stat develop...HEAD && git log --oneline develop..HEAD`

Expected: no whitespace errors; only the planned frontend, test, asset, README, and plan files appear; commits use conventional prefixes with detailed bodies.

- [ ] **Step 4: Present commit titles and descriptions for approval**

Do not push or merge. Show the user each conventional commit title and its detailed body, the final verification evidence, and the branch name. Wait for explicit approval before pushing the feature branch or merging it into `develop`.
