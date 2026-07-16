# Frontend Design Health Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining frontend design-health gaps as one MVVM-preserving hardening pass, then assign the final Nielsen score only from complete automated and emulator evidence.

**Architecture:** Keep Provider ViewModels responsible for asynchronous load, mutation, retry, failure, and targeted busy state. Keep controllers, focus, dialogs, navigation guards, contextual help, SnackBars, and responsive composition in the existing Flutter Views; extend the shared banner and add one shared task-help sheet without changing repositories, models, routes, or Supabase schema.

**Tech Stack:** Flutter 3, Material 3, Dart, Provider, flutter_test, Android Pixel 8 API 35 profile build.

---

## File Map

**Create:**

- `lib/ui/shared/task_help_sheet.dart` — shared, safe-area-aware task guidance bottom sheet.
- `test/ui/shared/task_help_sheet_test.dart` — help semantics, scrolling, dismissal, and state-preservation coverage.

**Modify:**

- `lib/ui/shared/app_banner.dart` — optional accessible action and responsive action layout.
- `lib/ui/hub/join_hub_viewmodel.dart` — directory, location, and membership recovery state.
- `lib/ui/hub/join_hub_screen.dart` — recoverable hub states, leave confirmation, task help, and compact Current Hub layout.
- `lib/ui/hub/widgets/hub_card.dart` — targeted Joining/Switching progress.
- `lib/ui/profile/profile_viewmodel.dart` — independent profile-load and sign-out failures.
- `lib/ui/profile/profile_screen.dart` — retryable Current Hub failure presentation.
- `lib/ui/split_board/split_board_viewmodel.dart` — cached feed retention and refresh failure state.
- `lib/ui/split_board/split_board_screen.dart` — inline cached-feed recovery while retaining filters and scroll.
- `lib/ui/split_board/deal_details_viewmodel.dart` — reliable participant state and two-phase mutations.
- `lib/ui/split_board/deal_details_screen.dart` — participant recovery, reliable action labels, confirmations, and task help.
- `lib/ui/split_board/create_deal_screen.dart` — dirty-form protection, unit dropdown, focus progression, first-error focus, and task help.
- `lib/ui/hub/create_hub_screen.dart` — dirty-form protection and focus progression.
- Existing focused tests under `test/ui/` — behavior, semantics, responsive, and regression coverage.

No data repository, domain model, migration, route, or product-navigation file changes are planned.

### Task 1: Add shared actionable feedback and task help

**Files:**

- Modify: `lib/ui/shared/app_banner.dart`
- Create: `lib/ui/shared/task_help_sheet.dart`
- Modify: `test/ui/shared/app_components_test.dart`
- Create: `test/ui/shared/task_help_sheet_test.dart`

- [ ] **Step 1: Write failing actionable-banner widget tests**

Add tests that tap an action, expose the action label to semantics, show a progress indicator while busy, and pump the banner at 320dp with 200% text without overflow.

```dart
testWidgets('AppBanner exposes a responsive retry action', (tester) async {
  var retries = 0;
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: AppBanner.error(
            message: 'Couldn’t refresh deals. Showing saved deals.',
            actionLabel: 'Try again',
            onAction: () => retries++,
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.widgetWithText(TextButton, 'Try again'));
  expect(retries, 1);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Run the shared component test and verify failure**

Run: `flutter test test/ui/shared/app_components_test.dart`

Expected: FAIL because `AppBanner` does not accept an action or busy state.

- [ ] **Step 3: Extend `AppBanner` without changing its visual language**

Add optional action fields to every constructor and render the action beside the message when space allows, otherwise below it. Preserve `Semantics(liveRegion: true)`, semantic theme colors, the current icon, 12dp radius, and current padding.

```dart
final String? actionLabel;
final VoidCallback? onAction;
final bool actionBusy;

Widget _action(Color foreground) => TextButton(
  onPressed: actionBusy ? null : onAction,
  style: TextButton.styleFrom(foregroundColor: foreground),
  child: actionBusy
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        )
      : Text(actionLabel!),
);
```

Use `LayoutBuilder` plus `MediaQuery.textScalerOf(context).scale(1)` to switch between a `Row` and `Column` when `maxWidth < 360` or text scale exceeds `1.3`.

- [ ] **Step 4: Write failing task-help tests**

Test that the sheet shows a title and ordered steps, scrolls at 200% text, has a visible Close action, and returns to the unchanged underlying screen.

```dart
await showTaskHelpSheet(
  context,
  title: 'Find your hub',
  steps: const [
    TaskHelpStep(
      icon: Icons.search_outlined,
      title: 'Search nearby',
      body: 'Search by hub, building, or area, or use the distance filter.',
    ),
  ],
);
```

- [ ] **Step 5: Implement the shared task-help sheet**

Create immutable `TaskHelpStep` values and one presentation function using `showModalBottomSheet<void>`, `SafeArea`, `DraggableScrollableSheet`, `ListView`, a 640dp readable content cap, Material outline icons, and a 48dp Close control.

```dart
class TaskHelpStep {
  const TaskHelpStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

Future<void> showTaskHelpSheet(
  BuildContext context, {
  required String title,
  required List<TaskHelpStep> steps,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _TaskHelpSheet(title: title, steps: steps),
  );
}
```

- [ ] **Step 6: Format, run focused tests, and commit**

Run: `dart format lib/ui/shared/app_banner.dart lib/ui/shared/task_help_sheet.dart test/ui/shared/app_components_test.dart test/ui/shared/task_help_sheet_test.dart && flutter test test/ui/shared/app_components_test.dart test/ui/shared/task_help_sheet_test.dart`

Expected: PASS with no overflow or semantics exceptions.

Commit:

```text
feat: add actionable frontend guidance
```

### Task 2: Make hub discovery and membership failures recoverable

**Files:**

- Modify: `lib/ui/hub/join_hub_viewmodel.dart`
- Modify: `test/ui/hub/join_hub_viewmodel_test.dart`

- [ ] **Step 1: Write failing directory-state tests**

Add tests proving that an initial repository failure exposes `directoryErrorMessage`, a successful empty directory stays a valid empty state, and cached hubs/search/filter survive a failed refresh.

```dart
expect(viewModel.directoryErrorMessage, isNotNull);
expect(viewModel.hasDirectoryData, isFalse);
expect(viewModel.filteredHubs, isEmpty);

await viewModel.refresh();
expect(viewModel.filteredHubs, contains(_colonHub));
expect(viewModel.directoryErrorMessage, contains('Couldn’t load hubs'));
```

- [ ] **Step 2: Write failing membership mutation tests**

Cover join, switch, and leave failure. Assert the old membership and both member counts are preserved, only the intended hub is busy, retry replays the last intent, and success clears the failure.

```dart
expect(viewModel.updatingHubId, 'magallanes');
expect(viewModel.isUpdatingHub('colon'), isFalse);
expect(viewModel.membershipErrorMessage, contains('current hub has not changed'));
expect(viewModel.canRetryMembership, isTrue);
```

- [ ] **Step 3: Run the ViewModel test and verify failure**

Run: `flutter test test/ui/hub/join_hub_viewmodel_test.dart`

Expected: FAIL because load failures become empty data and membership exceptions escape without retry state.

- [ ] **Step 4: Add explicit directory and membership state**

Retain the current repository calls and local count update logic, but add targeted state and a private retry intent.

```dart
enum _MembershipAction { join, leave }

class _MembershipRetry {
  const _MembershipRetry(this.action, [this.hubId]);
  final _MembershipAction action;
  final String? hubId;
}

String? _directoryErrorMessage;
String? _membershipErrorMessage;
String? _updatingHubId;
bool _isLeaving = false;
_MembershipRetry? _failedMembershipRetry;

bool get hasDirectoryData => _hubs.isNotEmpty;
bool get isUpdatingHub(String hubId) => _updatingHubId == hubId;
```

On refresh failure, preserve `_hubs`, `_joinedHubId`, `_searchQuery`, `_nearbyOnly`, and distances. On membership failure, preserve membership and counts and set consequence-based copy. Apply count changes only after repository success.

- [ ] **Step 5: Add retry commands**

Expose `retryMembership()` and `retryLocation()`. Retry the exact last join/leave intent, clear stale errors before work, and restore busy state during the retry.

```dart
Future<void> retryMembership() async {
  final retry = _failedMembershipRetry;
  if (retry == null) return;
  switch (retry.action) {
    case _MembershipAction.join:
      return join(retry.hubId!);
    case _MembershipAction.leave:
      return leave();
  }
}
```

- [ ] **Step 6: Format and rerun the ViewModel tests**

Run: `dart format lib/ui/hub/join_hub_viewmodel.dart test/ui/hub/join_hub_viewmodel_test.dart && flutter test test/ui/hub/join_hub_viewmodel_test.dart`

Expected: PASS, including current double-tap and local-count regressions.

### Task 3: Present accurate hub states, compact actions, and task help

**Files:**

- Modify: `lib/ui/hub/join_hub_screen.dart`
- Modify: `lib/ui/hub/widgets/hub_card.dart`
- Modify: `test/ui/hub/hub_screens_test.dart`
- Modify: `test/ui/frontend_responsive_test.dart`

- [ ] **Step 1: Write failing screen-state and confirmation tests**

Cover full initial failure with Retry instead of `No hubs yet`, cached-directory failure with feed retained, membership retry, location retry, targeted Joining/Switching labels, and leave confirmation with Stay/Leave hub paths.

```dart
expect(find.text("Couldn’t load hubs"), findsOneWidget);
expect(find.text('No hubs yet'), findsNothing);
await tester.tap(find.text('Leave hub'));
expect(find.text('Leave Colon Street Hub?'), findsOneWidget);
expect(find.text('Stay'), findsOneWidget);
```

- [ ] **Step 2: Add responsive Current Hub tests**

At Pixel 8 landscape width and normal text, assert the hub identity and both actions share one compact row. At 320dp and 200% text, assert the banner stacks and produces no overflow.

- [ ] **Step 3: Run focused screen tests and verify failure**

Run: `flutter test test/ui/hub/hub_screens_test.dart test/ui/frontend_responsive_test.dart`

Expected: FAIL because the current screen cannot distinguish initial failure, has no leave confirmation or retry actions, and always uses the vertically dominant Current Hub layout.

- [ ] **Step 4: Implement recoverable screen composition**

Render state in this order: initial loading; initial directory failure; normal content with optional cached-directory, membership, and location banners; confirmed empty/filter-empty states. Wire each banner to the matching ViewModel retry command.

Pass global mutation disabling and targeted progress separately to `HubCard`:

```dart
HubCard(
  hub: hub,
  isBusy: viewModel.isUpdatingMembership,
  isUpdatingThisHub: viewModel.isUpdatingHub(hub.id),
  busyLabel: viewModel.joinedHubId == null ? 'Joining…' : 'Switching…',
  // Existing callbacks remain unchanged.
)
```

The active action renders a small progress indicator plus text; unrelated actions remain disabled without displaying the wrong busy label.

- [ ] **Step 5: Add View-owned leave confirmation and contextual help**

Replace direct leave with a dialog containing the approved copy. Add an app-bar help icon with tooltip and semantic label `How to find and join a hub`, and provide only the three approved discovery steps through `showTaskHelpSheet`.

- [ ] **Step 6: Reflow the Current Hub banner by available width and text scale**

Use `LayoutBuilder`: one horizontal identity/action row at `maxWidth >= 560` and text scale `<= 1.3`; otherwise preserve the current stacked fallback. Keep the 720dp cap and 48dp membership controls.

- [ ] **Step 7: Format, test, and commit hub hardening**

Run: `dart format lib/ui/hub/join_hub_viewmodel.dart lib/ui/hub/join_hub_screen.dart lib/ui/hub/widgets/hub_card.dart test/ui/hub/join_hub_viewmodel_test.dart test/ui/hub/hub_screens_test.dart test/ui/frontend_responsive_test.dart && flutter test test/ui/hub test/ui/frontend_responsive_test.dart`

Expected: PASS with no directory failure represented as empty data.

Commit:

```text
fix: make hub membership states recoverable
```

### Task 4: Separate profile failures and preserve the Split Board on refresh

**Files:**

- Modify: `lib/ui/profile/profile_viewmodel.dart`
- Modify: `lib/ui/profile/profile_screen.dart`
- Modify: `lib/ui/split_board/split_board_viewmodel.dart`
- Modify: `lib/ui/split_board/split_board_screen.dart`
- Modify: `test/ui/profile/profile_viewmodel_test.dart`
- Modify: `test/ui/profile/profile_screen_test.dart`
- Modify: `test/ui/split_board/split_board_viewmodel_test.dart`
- Modify: `test/ui/split_board/split_board_screen_test.dart`

- [ ] **Step 1: Write failing profile recovery tests**

Assert a failed current-hub lookup produces `loadErrorMessage`, does not render `You haven’t joined a hub yet`, retries to the real hub, and remains independent from `signOutErrorMessage`.

```dart
expect(viewModel.loadErrorMessage, contains('Couldn’t load your current hub'));
expect(viewModel.signOutErrorMessage, isNull);
await viewModel.retryLoad();
expect(viewModel.currentHub?.name, 'Colon Street Hub');
```

- [ ] **Step 2: Implement independent profile outcomes**

Replace `_errorMessage` with `_loadErrorMessage` and `_signOutErrorMessage`. Make `_load` public through `retryLoad()`, assign `_currentHub` only after a successful lookup, preserve any cached hub when a retry fails, and show an actionable Current Hub banner on failure while leaving identity and Log out available.

- [ ] **Step 3: Write failing board cache tests**

Load deals successfully, fail the next refresh, and assert the same deals, search, category, status, sort, and scroll position remain while `refreshErrorMessage` is exposed. Cover Retry clearing the banner.

```dart
await viewModel.refresh();
expect(viewModel.deals, previousDeals);
expect(viewModel.refreshErrorMessage, contains('Showing the deals already loaded'));
expect(viewModel.searchQuery, 'rice');
```

- [ ] **Step 4: Implement initial versus cached board failures**

Keep `hasError` for failure without usable data and add `refreshErrorMessage` plus `isRefreshing` for failure with cached deals. Do not clear `_deals` or any filter in `refresh()`.

```dart
try {
  _deals = await _dealRepository.getDeals(_hubId);
  _hasError = false;
  _refreshErrorMessage = null;
} catch (_) {
  if (_deals.isEmpty) {
    _hasError = true;
  } else {
    _refreshErrorMessage =
        'Couldn’t refresh deals. Showing the deals already loaded.';
  }
}
```

Insert an `AppBanner.error` as the first sliver above filters when cached data remains. Its action calls `refresh()` and uses the banner busy state while refreshing.

- [ ] **Step 5: Verify route-return state preservation**

Add a widget test that enters search/filter state, scrolls the feed, opens details, returns, and verifies the query, filter selection, and visible scroll region remain unchanged.

- [ ] **Step 6: Format, run focused tests, and commit**

Run: `dart format lib/ui/profile lib/ui/split_board/split_board_viewmodel.dart lib/ui/split_board/split_board_screen.dart test/ui/profile test/ui/split_board/split_board_viewmodel_test.dart test/ui/split_board/split_board_screen_test.dart && flutter test test/ui/profile test/ui/split_board/split_board_viewmodel_test.dart test/ui/split_board/split_board_screen_test.dart`

Expected: PASS with cached content never replaced by a false empty/error state.

Commit:

```text
fix: preserve frontend data through refresh failures
```

### Task 5: Gate deal actions on reliable participant state

**Files:**

- Modify: `lib/ui/split_board/deal_details_viewmodel.dart`
- Modify: `lib/ui/split_board/deal_details_screen.dart`
- Modify: `test/ui/split_board/deal_details_viewmodel_test.dart`
- Modify: `test/ui/split_board/deal_details_screen_test.dart`

- [ ] **Step 1: Write failing participant-state tests**

Cover loading, failed, confirmed empty, and loaded participants. Assert Reserve and Cancel remain unavailable until the participant state is reliable, retry restores eligibility, and a failure never renders `Nobody has claimed a slot yet.`

```dart
expect(viewModel.isLoadingParticipants, isTrue);
expect(viewModel.canReserve, isFalse);
expect(viewModel.participantErrorMessage, isNull);

final failingRepository = _ControllableReservationRepository(
  deal: deal,
  currentUserId: 'visitor',
  failingParticipantCalls: const {1},
);
final failedViewModel = DealDetailsViewModel(
  reservationRepository: failingRepository,
  deal: deal,
  currentUserId: 'visitor',
);
await pumpEventQueue();
expect(failedViewModel.hasReliableParticipantState, isFalse);
expect(failedViewModel.canReserve, isFalse);
```

Use a test-only controllable subclass so production repository contracts remain untouched:

```dart
class _ControllableReservationRepository extends MockReservationRepository {
  _ControllableReservationRepository({
    required super.deal,
    required super.currentUserId,
    this.failingParticipantCalls = const <int>{},
  });

  final Set<int> failingParticipantCalls;
  int participantCalls = 0;

  @override
  Future<List<Reservation>> getParticipants(String dealId) {
    participantCalls++;
    if (failingParticipantCalls.contains(participantCalls)) {
      throw StateError('participant table unavailable');
    }
    return super.getParticipants(dealId);
  }
}
```

For initial failure use `{1}`; for mutation-success/follow-up-failure use `{2}` after allowing the constructor load to complete.

- [ ] **Step 2: Write the mutation/refresh separation regression test**

Make `reserveSlot` return an updated deal and make the following `getParticipants` fail. Assert the deal’s new slot count is preserved, `errorMessage` stays null, and only `participantErrorMessage` is set.

- [ ] **Step 3: Run the focused tests and verify failure**

Run: `flutter test test/ui/split_board/deal_details_viewmodel_test.dart test/ui/split_board/deal_details_screen_test.dart`

Expected: FAIL because participant failures currently become a confirmed empty list and can enable Reserve.

- [ ] **Step 4: Implement reliable participant state**

Rename the ambiguous loading state and add a participant-specific error contract.

```dart
bool _isLoadingParticipants = true;
String? _participantErrorMessage;

bool get hasReliableParticipantState =>
    !_isLoadingParticipants && _participantErrorMessage == null;

bool get canReserve =>
    hasReliableParticipantState &&
    !holdsSlot &&
    !isFull &&
    !deadlinePassed &&
    !isClosed;
```

`retryParticipants()` preserves any cached participant list for display but marks it unreliable until the fetch succeeds.

- [ ] **Step 5: Split mutation success from participant refresh**

First await the reservation mutation and assign `_deal`. Only mutation exceptions set `errorMessage`. Then call the participant loader; a follow-up fetch failure sets only `participantErrorMessage` and leaves the updated deal intact.

- [ ] **Step 6: Render the four participant outcomes and reliable action copy**

Render `Loading participants…`, actionable Retry, confirmed empty, or the existing list in that order. Use `Checking availability…` during load and `Participants unavailable` after failure; keep the bottom action disabled in both states.

- [ ] **Step 7: Add the approved destructive confirmations and task help**

Confirm `Cancel my slot` with copy explaining another member may take it. Confirm `I’ve bought it` with copy explaining reservations become locked. Keep the existing host cancel/refund confirmation. Add an app-bar help control with the approved payment, physical share, slot, pickup, and role guidance.

- [ ] **Step 8: Format, run all detail tests, and commit**

Run: `dart format lib/ui/split_board/deal_details_viewmodel.dart lib/ui/split_board/deal_details_screen.dart test/ui/split_board/deal_details_viewmodel_test.dart test/ui/split_board/deal_details_screen_test.dart && flutter test test/ui/split_board/deal_details_viewmodel_test.dart test/ui/split_board/deal_details_screen_test.dart`

Expected: PASS with no action enabled from unknown participant data.

Commit:

```text
fix: gate deal actions on reliable participant data
```

### Task 6: Protect and streamline Post Deal

**Files:**

- Modify: `lib/ui/split_board/create_deal_screen.dart`
- Modify: `test/ui/split_board/create_deal_screen_test.dart`
- Modify: `test/ui/frontend_responsive_test.dart`

- [ ] **Step 1: Write failing dirty-exit tests**

Cover untouched Back, app-bar/system Back after editing, Keep editing preserving every value, Discard popping exactly once, repeated Back not stacking dialogs, failed publish remaining dirty, and successful publish popping without a discard prompt.

```dart
await tester.enterText(find.byKey(const Key('deal-title-field')), 'Rice Sack');
await tester.pageBack();
expect(find.text('Discard these details?'), findsOneWidget);
await tester.tap(find.text('Keep editing'));
expect(find.text('Rice Sack'), findsOneWidget);
```

- [ ] **Step 2: Write failing unit and focus tests**

Assert there is one labeled `DropdownButtonFormField<DealUnit>`, all seven existing values remain selectable using full names/symbols, the selected value is announced, Next/Done actions are logical, and invalid submit focuses the first invalid field.

```dart
expect(find.byKey(const Key('deal-unit-field')), findsOneWidget);
expect(find.byType(ChoiceChip), findsNWidgets(DealCategory.values.length));
expect(find.text('Kilograms (kg)'), findsOneWidget);
final titleField = tester.widget<TextFormField>(
  find.byKey(const Key('deal-title-field')),
);
expect(titleField.focusNode?.hasFocus, isTrue);
```

- [ ] **Step 3: Run the create-deal tests and verify failure**

Run: `flutter test test/ui/split_board/create_deal_screen_test.dart test/ui/frontend_responsive_test.dart`

Expected: FAIL because Back discards silently, unit selection uses seven chips, and invalid submit does not focus the first invalid field.

- [ ] **Step 4: Add View-owned dirty navigation protection**

Track `_isDirty`, `_allowPop`, and `_discardDialogOpen` in `_CreateDealScreenState`. Mark dirty from every text, category, unit, deadline set, and deadline clear change. Wrap the Scaffold in `PopScope<Deal>` and show the approved Keep editing/Discard dialog only for a dirty form.

```dart
PopScope<Deal>(
  canPop: !_isDirty || _allowPop,
  onPopInvokedWithResult: (didPop, result) {
    if (!didPop) _confirmDiscard();
  },
  child: Scaffold(/* existing app */),
)
```

On successful submit, set `_allowPop = true` and `_isDirty = false` before returning the created deal. Failed submit leaves controllers and dirty state untouched.

- [ ] **Step 5: Replace the unit chip wall with one native dropdown**

Keep `_unit` and `DealUnit` unchanged. Map the current values to `Kilograms (kg)`, `Litres (L)`, `Pieces`, `Packs`, `Bottles`, `Cans`, and `Sachets`.

```dart
DropdownButtonFormField<DealUnit>(
  key: const Key('deal-unit-field'),
  value: unit,
  decoration: const InputDecoration(
    labelText: 'Unit',
    helperText: 'Choose how the total amount is measured.',
  ),
  items: DealUnit.values
      .map((value) => DropdownMenuItem(
            value: value,
            child: Text(_unitDisplayName(value)),
          ))
      .toList(),
  onChanged: onChanged,
)
```

- [ ] **Step 6: Add keyboard progression and first-invalid focus**

Create and dispose FocusNodes for title, description, total price, amount, slots, and pickup. Assign Next/Done actions and use the existing validators in field order after `FormState.validate()` to request focus on the first failure. Use `Scrollable.ensureVisible` for a deadline error.

- [ ] **Step 7: Add contextual Post Deal help**

Add a 48dp app-bar help action with tooltip `How to post a deal`. Supply only the existing flow: product, split, pickup/deadline, review, publish. Do not add another route or permanent instructional panel.

- [ ] **Step 8: Format, test, and commit**

Run: `dart format lib/ui/split_board/create_deal_screen.dart test/ui/split_board/create_deal_screen_test.dart test/ui/frontend_responsive_test.dart && flutter test test/ui/split_board/create_deal_viewmodel_test.dart test/ui/split_board/create_deal_screen_test.dart test/ui/frontend_responsive_test.dart`

Expected: PASS with every existing unit, preview, validation, and publish behavior retained.

Commit:

```text
feat: protect and streamline deal creation
```

### Task 7: Protect Register Hub details

**Files:**

- Modify: `lib/ui/hub/create_hub_screen.dart`
- Modify: `test/ui/hub/hub_screens_test.dart`
- Modify: `test/ui/frontend_responsive_test.dart`

- [ ] **Step 1: Write failing registration-exit tests**

Cover untouched Back, changed name/type/coordinates/location capture, Keep editing, Discard, repeated Back, submission failure, and successful registration. Verify captured location values count as changed details.

- [ ] **Step 2: Write failing focus and large-text tests**

Assert name → latitude → longitude keyboard progression, first-invalid focus, coordinate stacking at 320dp/200% text, and no dialog or horizontal overflow.

- [ ] **Step 3: Run the focused tests and verify failure**

Run: `flutter test test/ui/hub/hub_screens_test.dart test/ui/frontend_responsive_test.dart`

Expected: FAIL because registration currently discards changed values without confirmation and has incomplete keyboard progression.

- [ ] **Step 4: Add the same View-owned safe-exit contract**

Track dirty and dialog state locally, mark changes from name/type/coordinates and successful location capture, and wrap the current Scaffold in `PopScope<Hub>`. Use the approved title `Discard these details?`, Register Hub-specific unpublished copy, and Keep editing/Discard actions.

- [ ] **Step 5: Add focus progression without changing validation ownership**

Create name, latitude, and longitude FocusNodes; pass them into `_CoordinateFields`; request the first invalid field after current ViewModel validators run. Clear dirty state only immediately before a successful result pop.

- [ ] **Step 6: Format, test, and commit**

Run: `dart format lib/ui/hub/create_hub_screen.dart test/ui/hub/hub_screens_test.dart test/ui/frontend_responsive_test.dart && flutter test test/ui/hub/create_hub_viewmodel_test.dart test/ui/hub/hub_screens_test.dart test/ui/frontend_responsive_test.dart`

Expected: PASS with location, duplicate detection, registration, and responsive behavior unchanged apart from safe recovery.

Commit:

```text
feat: protect hub registration details
```

### Task 8: Run the cross-screen accessibility and responsive quality gate

**Files:**

- Modify as failures require: the production and test files changed in Tasks 1–7
- Verify: `test/ui/frontend_responsive_test.dart`
- Verify: all focused widget tests under `test/ui/`

- [ ] **Step 1: Add the complete viewport matrix to responsive tests**

Pump changed screens at 320dp, Pixel 8 portrait, Pixel 8 landscape, and 1200dp tablet width. Repeat critical hub, form, banner, participant, and help states with `TextScaler.linear(2)`.

- [ ] **Step 2: Add semantics assertions**

Verify live errors, Retry actions, busy labels, selected unit, disabled participant action, destructive dialog labels, and icon-only Help controls. Every control remains at least 44dp, with membership and primary controls at least 48dp.

- [ ] **Step 3: Run all UI tests**

Run: `flutter test test/ui`

Expected: PASS with no overflow, semantics exception, lost navigation state, or false empty state.

- [ ] **Step 4: Correct only evidence-backed defects**

If a matrix test fails, fix the smallest responsible screen/shared component and add the exact failing state as a regression. Do not change the theme, typography, navigation, repository APIs, models, routes, or schema.

- [ ] **Step 5: Format and rerun the UI suite**

Run: `dart format lib/ui test/ui && flutter test test/ui`

Expected: PASS.

Commit only if this gate required corrections:

```text
fix: complete frontend accessibility hardening
```

### Task 9: Verify the full app, emulator experience, performance, and score

**Files:**

- Verify: all tracked project files
- Preserve untracked: `AGENTS.md`

- [ ] **Step 1: Verify formatting without modifying files**

Run: `dart format --output=none --set-exit-if-changed lib test`

Expected: exit 0 with no files requiring formatting.

- [ ] **Step 2: Run analyzer and complete automated suite**

Run: `flutter analyze && flutter test`

Expected: analyzer reports `No issues found!` and every test passes.

- [ ] **Step 3: Launch the Pixel 8 API 35 profile build**

Run: `flutter devices` followed by `flutter run --profile -d emulator-5554` using the discovered Pixel 8 identifier if it differs.

Expected: the profile build launches successfully with no runtime exception.

- [ ] **Step 4: Navigate every changed success and failure flow**

Exercise hub initial failure/retry, cached refresh failure, join, switch, leave cancel/confirm/retry, profile failure/retry/logout, board refresh with retained feed, filter/scroll route return, participant failure/retry, reserve/cancel, purchased/cancel-deal confirmations, dirty Post Deal/Register Hub exits, failed submissions, and each task-help sheet.

- [ ] **Step 5: Repeat visual and accessibility variants**

Verify light/dark, portrait/landscape, 200% text, narrow phone, Pixel 8 phone, and tablet-width layouts. Inspect the semantics tree for live failures, busy controls, selected units, disabled actions, and help controls. No horizontal overflow or clipped primary action is acceptable.

- [ ] **Step 6: Measure profile-mode frame performance**

Clear the VM timeline, repeat the previous keyboard-free hub-list and Post Deal scroll traces, and compare `Frame` plus `GPURasterizer::Draw` durations with the established baseline. The hardening must not reintroduce frames over 16.7ms in the form scroll or materially regress hub-list performance.

- [ ] **Step 7: Re-audit the same 40-point Nielsen table**

Score system status, real-world match, user control, consistency, error prevention, recognition, efficiency, minimal design, error recovery, and help from the finished evidence. Award 4/4 only where all defined loading, success, empty, failure, retry, destructive, accessibility, and responsive states pass. Report any remaining deduction honestly instead of manufacturing 40/40.

- [ ] **Step 8: Inspect branch and commit history**

Run: `git status --short --branch && git log --oneline --decorate develop..HEAD`

Expected: only the user-owned `AGENTS.md` remains untracked; implementation commits use natural Conventional Commit titles and contain no assistant or tool branding. Do not push or merge until the user explicitly requests it.
