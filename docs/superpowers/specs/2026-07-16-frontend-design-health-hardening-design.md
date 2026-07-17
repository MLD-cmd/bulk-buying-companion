# Frontend Design Health Hardening

**Status:** Approved
**Date:** 2026-07-16
**Target branch:** `feat/frontend-polish-performance`

## Goal

Close the remaining gaps in the existing 40-point Nielsen design-health audit as one coordinated frontend hardening pass. The work must preserve the current campus split-share product, its MVVM boundaries, its routes, its repositories, its domain models, and its Supabase schema.

The final score is assigned only after the complete implementation is verified. Individual changes do not receive provisional points, and a 40/40 result is reported only when the final emulator, accessibility, state, and regression evidence supports every score.

## Product Boundaries

This design improves the behavior and presentation of existing tasks:

- finding, joining, switching, and leaving a hub;
- viewing the current profile and hub;
- browsing and filtering the Split Board;
- viewing a deal and managing a reservation;
- registering a hub; and
- posting a deal.

It does not add new navigation destinations, payments, messaging, favorites, activity history, bulk administration, a help center, or new backend persistence. Repository interfaces, domain models, migrations, and existing routes remain unchanged.

## Architecture

The implementation continues to use MVVM:

- **ViewModels** own asynchronous loading, mutation, retry, error, and targeted busy state. They translate repository failures into user-facing outcomes and never expose failed loading as valid empty data.
- **Views** own text controllers, focus, confirmation dialogs, navigation guards, contextual help sheets, SnackBars, and responsive layout.
- **Repositories** continue to own data access and domain failure contracts. No repository API changes are required.
- **Shared UI components** provide one consistent actionable banner and task-help presentation instead of feature-specific duplicates.

## Hub Discovery and Membership

### Directory state

`JoinHubViewModel` will distinguish loading, loaded, cached-with-refresh-error, and failed-without-data states.

- An initial directory failure shows a full `AppMessageState` with a clear message and Retry action.
- A refresh failure retains previously loaded hubs and shows an actionable inline banner.
- A directory failure must never display `No hubs yet`.
- Search and nearby-filter state remain intact during retry.

### Membership mutations

The ViewModel will expose the hub being updated, whether a leave is in progress, a membership failure message, and a retry command for the last failed intent.

- Join, switch, and leave update local membership and member counts only after repository success.
- Failure preserves the previous membership and counts.
- Only the affected card displays `Joining…` or `Switching…`; other membership actions remain disabled while the operation is in flight.
- The Current Hub banner displays `Leaving…` while a leave is in progress.
- Successful operations provide concise confirmation through the existing screen and a SnackBar where the state change is not otherwise immediately obvious.

Leaving a hub requires confirmation:

- Title: `Leave <hub name>?`
- Message: `You’ll need to join a hub again before you can open its Split Board.`
- Actions: `Stay` and `Leave hub`

The existing inline switch confirmation remains because it already keeps the target hub visible and avoids an unnecessary modal.

### Responsive Current Hub banner

The banner uses one horizontal row when width and text scale allow it: hub identity on the left and the two actions on the right. Narrow screens and enlarged text retain the stacked layout. The same 720dp content cap remains in place.

## Profile Accuracy and Recovery

`ProfileViewModel` will separate current-hub loading failures from sign-out failures and expose a retry command for profile loading.

- A failed hub lookup is not represented as confirmed no-membership state.
- Identity and Log out remain available when only the hub lookup fails.
- The Current Hub section shows an actionable retry banner.
- Sign-out errors remain beside the Log out action and do not overwrite load state.

## Split Board Refresh Recovery

The Split Board keeps its existing loading, search, filtering, sorting, lazy feed, and empty states.

- Initial failure without deals uses the existing full error state.
- Refresh failure with cached deals keeps the feed visible and adds an inline retry banner.
- Search, filters, sort selection, and scroll position survive navigation to Deal Details and back.
- Clear filters continues to clear search, category, and status together.

## Deal Participant Reliability

`DealDetailsViewModel` will separate participant loading and participant failure from reservation mutation failure.

Participant state has four explicit outcomes:

1. `Loading participants…`
2. actionable failure with Retry;
3. confirmed empty state; and
4. loaded participant list.

Reservation eligibility is available only when participant state is reliable. While participants are loading, the action reads `Checking availability…`; after failure it reads `Participants unavailable`. The action remains disabled in both cases.

If a reservation mutation succeeds but the follow-up participant refresh fails, the updated deal is preserved. The UI reports only the participant refresh problem and allows retry; it must not claim that the mutation failed.

High-consequence participant actions receive confirmation:

- cancelling the current student’s claimed slot explains that another member may take it;
- marking a deal purchased explains that reservations become locked; and
- host deal cancellation keeps the existing paid-student refund warning.

Reserving an available slot remains a direct action because it is reversible and already provides immediate state feedback.

## Safe Form Exit

Post Deal and Register Hub retain their current fields, validation, ViewModels, and submit behavior.

The Views track whether any field or selector has changed. Back exits immediately for untouched forms. A changed form shows:

- Title: `Discard these details?`
- Message tailored to the form, stating that the entered details have not been published or registered.
- Actions: `Keep editing` and `Discard`.

`Keep editing` closes the dialog without changing values. `Discard` intentionally clears the dirty state and pops once. Repeated Back events cannot create duplicate dialogs. A failed submission preserves every value and remains dirty; successful submission pops normally without a discard prompt.

This is unsaved-change protection, not a persistent draft system. It prevents accidental loss without introducing storage or a new product workflow.

## Form Recognition and Efficiency

The Post Deal unit selector changes from seven simultaneous chips to one labeled dropdown. Options use full names and symbols, such as `Kilograms (kg)`, `Litres (L)`, and `Bottles`.

- Every existing `DealUnit` remains selectable.
- The selected unit remains part of the same draft and validation flow.
- Numeric and text fields use logical Next/Done keyboard actions.
- Invalid submission scrolls or focuses to the first invalid section instead of leaving the user to locate the problem.
- Existing live split, physical-share, and review previews remain unchanged.

## Contextual Help

Help stays inside the current tasks rather than becoming a new destination.

A shared task-help bottom sheet presents concise, scrollable guidance for the existing complex flows:

- **Find your hub:** search or use distance, review the hub type, then join or switch.
- **Post a deal:** enter the product, define the split, set pickup, review, and publish.
- **Deal details:** review payment and physical share, check slots and pickup, then reserve or manage the deal according to the user’s role.

Help controls have visible tooltips and semantic labels. Closing help returns to the unchanged screen and preserves all input, filters, and scroll state. Inline section descriptions remain the primary guidance; the sheet provides task-level explanation without adding permanent visual noise.

## Shared Components

### Actionable banner

`AppBanner` gains an optional action label, callback, and busy state.

- The banner preserves its live-region semantics.
- Action and message render side by side when space allows and stack under narrow width or enlarged text.
- Error, notice, and success tones continue to use the existing semantic color system.

### Task-help presentation

One shared presentation function or widget renders task-help content in a safe-area-aware, scrollable bottom sheet with a readable maximum width. Individual screens supply only their task-specific title and steps.

## Accessibility and Responsive Requirements

- Interactive controls retain at least 44×44dp targets; hub membership controls remain 48dp.
- Loading and failure changes are announced through live semantics.
- Busy controls expose their current action in text, not color alone.
- Unit selection exposes the selected value to assistive technology.
- Help, retry, confirmation, and discard controls have clear labels and logical focus order.
- All changed states must work at 320dp width, 200% text, Pixel 8 portrait, Pixel 8 landscape, tablet width, light theme, and dark theme.
- No horizontal overflow is permitted.

## Error Copy Principles

Messages state what failed, what was preserved, and what the user can do next.

Examples:

- `Couldn’t load hubs. Check your connection and try again.`
- `Couldn’t join this hub. Your current hub has not changed.`
- `Couldn’t leave the hub. You are still a member.`
- `Couldn’t load who is in this deal. Try again before reserving a slot.`
- `Couldn’t refresh deals. Showing the deals already loaded.`

Internal exception details and backend terminology never appear in the interface.

## Verification Strategy

Implementation follows red-green testing for each behavioral change.

### ViewModel coverage

- Hub directory initial failure, cached refresh failure, membership failure, retry, preserved counts, and targeted busy state.
- Profile load failure and retry independent from sign-out failure.
- Participant loading, failure, retry, reliable-action gating, and mutation-success/refresh-failure separation.
- Board cached data retained after refresh failure.

### Widget coverage

- Correct loading, failure, retry, empty, cached, and success states.
- Leave, cancel-slot, purchased, discard, and keep-editing confirmation paths.
- Form values preserved after failure and after cancelling discard.
- Unit dropdown contents, selection, semantics, and 200% text behavior.
- Contextual help content, scrolling, dismissal, and state preservation.
- Landscape Current Hub compaction and narrow/large-text fallback.
- Actionable banner semantics and responsive reflow.

### Release gates

- `dart format --output=none --set-exit-if-changed` on all changed Dart files.
- `flutter analyze` with no issues.
- Complete `flutter test` suite with zero failures.
- Pixel 8 API 35 profile build navigation through all changed flows.
- Light, dark, portrait, landscape, narrow, wide, and 200% text visual checks.
- Profile-mode timeline comparison to ensure the new state UI does not regress scrolling performance.
- A fresh Nielsen audit using the same 40-point rubric and evidence from the completed implementation.

## Commit Conventions

The specification uses:

```text
docs: define frontend design health hardening
```

The implementation will use a natural Conventional Commit title and a detailed body describing the behavior, architecture, tests, and measured verification. Commit metadata and descriptions must not include tool or assistant branding.
