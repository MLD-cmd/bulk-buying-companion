# Frontend Redesign Design

Date: 2026-07-16
Status: Approved and implemented on feature branch; awaiting release review

## Goal

Redesign the existing Flutter interface into a cohesive, accessible campus bulk-buying experience without expanding the product's feature set. The implementation should preserve the current repositories, view models, validation rules, deal lifecycle, Supabase schema, and user workflows while improving information hierarchy, typography, spacing, iconography, responsive behavior, and interaction clarity.

The target is an excellent usability audit across Nielsen's ten heuristics. A literal 40/40 score cannot be guaranteed by styling alone, but every acceptance criterion below is intended to eliminate the weaknesses identified in the initial 23/40 source review.

## Approved Direction

The approved direction is a clean, restrained campus co-op interface:

- Modern sans-serif typography rather than decorative or vintage styling.
- Neutral surfaces with teal as the primary action color and blue-green supporting tones.
- One consistent outlined icon family.
- Minimal card chrome; use dividers and spacing for most structure.
- Filled treatment only for the primary action in a decision area.
- Search instructions inside search fields rather than split across labels and placeholders.
- Circular avatars and icon containers with a shared size and shape system.
- Mobile-first layouts with 44-48 logical-pixel touch targets.

## Scope

### Included screens and states

1. Authentication in login mode.
2. Authentication in registration mode.
3. Hub discovery and current-hub state.
4. Hub registration.
5. Split Board deal feed.
6. Deal details for participant and host lifecycle states.
7. Deal creation: Product section.
8. Deal creation: Split section.
9. Deal creation: Pickup section and publish review.
10. Profile with current hub and logout.
11. Existing loading, empty, filtered-empty, error, disabled, pending, success, and destructive-confirmation states.

### Explicit non-goals

The redesign will not add:

- In-app payment.
- Chat or messaging.
- A new My Deals destination.
- A new bottom-navigation system.
- Push-notification preferences.
- Student verification badges or verification infrastructure.
- A commitments dashboard or weekly metrics.
- Receipt scanning, product photography, or map infrastructure.
- New database tables, Supabase functions, or lifecycle states.
- Changes to reservation, payment, purchase, pickup, cancellation, or membership business rules.

## Information Architecture

### Entry routing

- Signed-out users see the existing authentication experience.
- Newly registered users continue to hub discovery.
- A returning signed-in user with no joined hub sees hub discovery.
- A returning signed-in user with a joined hub opens that hub's Split Board after membership resolution.
- The Split Board exposes the existing hub directory, and the hub directory exposes the existing profile screen.

This removes a repeated hub-selection step without inventing a new destination.

### Navigation model

- Use standard app-bar back navigation for pushed screens.
- Keep screen titles and current context visible in the app bar.
- Do not add bottom navigation.
- Preserve the existing route structure wherever possible.
- Destructive actions remain secondary and require the existing confirmation behavior.

## Design System

### Color roles

Colors are semantic tokens, not one-off screen values.

| Token | Light value | Purpose |
|---|---|---|
| `primary` | `#0F766E` | Primary actions, progress, selected controls |
| `onPrimary` | `#FFFFFF` | Content on primary |
| `background` | `#F6FAF9` | App background |
| `surface` | `#FFFFFF` | Inputs and necessary raised surfaces |
| `foreground` | `#102A2E` | Primary text and icons |
| `mutedForeground` | `#52666A` | Secondary text |
| `outline` | `#CBD8D6` | Dividers and input borders |
| `success` | `#166534` | Joined, open, paid, collected states |
| `successContainer` | `#E7F6EC` | Subtle success background |
| `warning` | `#8A4B08` | Filling-fast and deadline urgency |
| `warningContainer` | `#FFF3D6` | Subtle warning background |
| `error` | `#B42318` | Errors and destructive actions |
| `errorContainer` | `#FDECEA` | Error background |

The dark theme uses the same semantic roles with dark teal-neutral surfaces and WCAG AA contrast. No screen derives UI fills from arbitrary series colors.

### Typography

- `Manrope` for body text, labels, inputs, buttons, and numeric details.
- `Outfit` for screen titles and section headings.
- Bundle fonts as application assets so the UI does not require a runtime network request.
- Use four semantic levels only: screen title, section title, body, supporting label.
- Use weights 400 and 500; hierarchy comes primarily from size, spacing, and position.
- Supporting text remains at least 14 logical pixels on mobile.

### Geometry and spacing

- Base spacing unit: 4 logical pixels.
- Main spacing values: 4, 8, 12, 16, 20, 24, and 32.
- Screen horizontal padding: 20 on phones, capped content width on tablets and desktop.
- Form field and primary button height: at least 52.
- Small controls and icon buttons: at least 44 square.
- Standard control radius: 12.
- Necessary surface radius: 16.
- Avatars, status dots, and icon containers: circular.
- Avoid nested cards; prefer whitespace and one-pixel dividers.

### Icons

- Use Material Symbols/Material icons already available through Flutter.
- Use the outlined family consistently.
- Standard inline size: 20.
- Standard leading icon container: 40-44, circular.
- Icon-only actions must retain tooltips and semantic labels.
- Important or unfamiliar actions use an icon plus visible text.

## Shared Components

The implementation should centralize repeated styling instead of duplicating `styleFrom`, colors, and radii across screens.

### Theme-owned components

`AppTheme` will define:

- Light and dark color schemes.
- Text theme and font families.
- App bar theme.
- Filled, outlined, text, icon, and floating-action button themes.
- Input decoration theme.
- Chip theme.
- Card theme.
- Divider theme.
- Progress indicator theme.
- Snack bar and dialog themes.

### Reusable widgets

- `AppScreenHeader`: consistent title, optional subtitle, and labeled actions.
- `AppSectionHeader`: section title and optional trailing context.
- `AppStatusBadge`: semantic lifecycle status with text plus color.
- `AppMessageState`: loading-adjacent, empty, filtered-empty, and retryable error presentation.
- `AppBanner`: error, notice, and success messages with live-region semantics.
- `AppFormSection`: heading, supporting text, and grouped fields.
- `AppIconContainer`: consistent circular leading icon treatment.
- `DealActionBar`: bottom action area for participant/host actions on deal details.

Existing domain widgets such as `HubCard` and `DealCard` remain domain-specific but consume the shared theme and primitives.

## Screen Designs

### Authentication

- Retain the existing login/register modes and validation behavior.
- Keep the basket brand mark, product name, mode selector, fields, banners, and one primary submit action.
- Remove marketing sections, password recovery, social login, and other unsupported features.
- Registration contains full name, email, password, and confirmation fields.
- Use consistent prefix icons and password-visibility affordances.

### Hub discovery

- App bar title remains `Find your hub`.
- Profile and Register hub remain existing destinations.
- Search uses one field with `Search hubs, buildings, areas…` inside the field and a search icon.
- The nearby filter remains the existing `Within 2 km` capability.
- Hub rows show only name, type, member count, distance, membership state, and Join/Switch action.
- Current-hub access remains prominent without introducing dashboard content.

### Hub registration

- Preserve hub name, Dormitory/Area hub type, Use my current location, latitude, longitude, validation, and submit behavior.
- Center the location icon and label as one group in the full-width location action.
- Keep latitude and longitude visible/editable because they are part of the current implementation.
- Do not add an address search, map, or geocoding dependency.

### Split Board

- App bar shows `Split Board` and the current hub name.
- Search uses one field with `Search by product name` inside the control.
- Keep category, status, and sort functionality but move secondary choices behind one labeled Filters action on narrow screens.
- Active filters appear as removable text chips; do not add new filter dimensions.
- Deal rows prioritize title, per-share price, physical share, available slots, deadline, and lifecycle status.
- Pickup location and other secondary information remain available on deal details.
- Keep the existing Post a deal floating action as the only primary feed action.

### Deal details

- Lead with deal title, category, lifecycle status, per-share cost, and physical share.
- Preserve slots progress, participants, organiser, pickup, deadline, uneven-split explanation, payment controls, collection controls, purchase action, reservation action, cancellation action, and refund warning.
- Use a bottom action area so the relevant primary action remains reachable.
- Participant and host layouts share the same information hierarchy; only authorized controls differ.
- Cancellation and reservation cancellation must not share the positive primary style.

### Deal creation

- Keep one route and one `CreateDealViewModel`; visually group the existing form into Product, Split, and Pickup sections.
- Product contains name, optional description, and category.
- Split contains total price, total amount, unit, number of shares, cost preview, physical-share preview, and uneven-split explanation.
- Pickup contains pickup location and optional deadline.
- The final section shows a concise review using values already present in the draft.
- Preserve all existing validation rules and submission behavior.
- State remains local to the creation screen while the user moves between sections.

### Profile

- Preserve avatar initials, display name, email, current hub or no-hub state, error banner, and logout.
- Do not add edit profile, verification, commitments, settings, help, or notification destinations.

## Data and State Flow

- Repositories and view-model public contracts remain unchanged unless routing the returning user requires a small read-only membership resolver.
- UI widgets observe existing `ChangeNotifier` state through Provider.
- Form fields continue to validate through their existing view models.
- Deal creation uses a single state owner across all three visual sections so no data is lost when moving backward.
- Successful create/register/reserve/purchase/cancel actions continue returning updated domain objects or refreshing their owning view model.
- Snack bars remain the transient success-feedback mechanism.
- Errors remain in the current screen and preserve entered data.

## Responsive and Accessibility Requirements

- Support phone widths from 320 logical pixels without horizontal scrolling or overflow.
- Cap readable content width on tablet/desktop rather than stretching forms indefinitely.
- Reflow paired fields vertically when large text or narrow width makes two columns unsafe.
- Support text scale up to 200% for the primary flows.
- All tap targets are at least 44 by 44.
- All normal text meets WCAG AA contrast of 4.5:1.
- Status never relies on color alone; every state includes a text label.
- Loading, error, notice, and success changes use live-region semantics where appropriate.
- Keyboard focus remains visible on desktop/web.
- Form labels remain programmatically associated with controls.

## Error and Edge States

- Authentication preserves inline field errors and account-confirmation notices.
- Hub discovery preserves loading, location failure, no hubs, no nearby hubs, and no search matches.
- Hub registration preserves locating, captured coordinates, location failure, invalid coordinates, submit failure, and disabled submit states.
- Split Board preserves loading, retryable error, empty hub, no filter matches, refresh, and post-success feedback.
- Deal creation preserves field validation, invalid physical splits, uneven monetary splits, deadline validation, submit failure, and loading.
- Deal details preserves full, deadline passed, reservation failure, paid reservation lock, host-only lifecycle controls, cancellation warnings, and completion states.
- Profile preserves loading, missing user, repository error, and sign-out failure.

## Testing Strategy

### Existing regression suite

- All existing analyzer checks and tests must continue passing.
- Repository, model, and view-model behavior should not change as part of styling work.

### New widget coverage

- Authentication modes render the correct fields and submit labels.
- Hub and board search fields contain their prompts inside the controls.
- Hub location action centers its icon/label and retains coordinate fields.
- Split Board filters preserve category/status/sort behavior.
- Deal details renders the correct action hierarchy for participant and host lifecycle states.
- Deal creation retains data while moving between its visual sections.
- Profile contains only current supported information and actions.

### Layout and accessibility coverage

- Pump representative screens at 320, 390, and tablet widths.
- Pump representative screens at 200% text scaling.
- Assert no overflow exceptions in core flows.
- Verify semantic labels for icon-only actions, status badges, progress, and live banners.
- Verify minimum target sizes for compact actions.
- Manually inspect light and dark themes on a real emulator before completion.

## Acceptance Criteria

The redesign is complete when:

1. Every existing screen uses the shared theme and component rules.
2. No unsupported feature from the non-goals list appears in the UI.
3. Hub and board search prompts are inside their fields.
4. The location action is centered and coordinate editing remains available.
5. Deal cards and details prioritize per-share value and physical share.
6. Deal creation is visually divided into Product, Split, and Pickup without losing existing inputs or validation.
7. The relevant deal-details action remains reachable and destructive actions are visually distinct.
8. Light and dark themes use stable semantic colors without brown or series-derived drift.
9. Core flows work at 320-pixel width and 200% text scaling without overflow.
10. Existing tests pass and the new layout/accessibility tests pass.
