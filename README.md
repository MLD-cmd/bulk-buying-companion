# Bulk Buying Companion

A Flutter app that helps students in a campus or dorm split the cost of
buying in bulk. Students join a "hub" (a dorm, campus, or org), post deals to
that hub's Split Board, reserve a share, and track the deal from posting
through payment, purchase, and pickup.

## Features

- **Hubs** — create or join a campus/dorm hub by proximity (device geolocation)
  or by browsing/searching nearby hubs, with duplicate-hub checks on creation.
- **Split Board** — browse a hub's open deals, filter and search them, and see
  personalized deal recommendations based on past activity.
- **Create a deal** — post a bulk-buy deal with automatic per-share cost
  splitting (`CostSplit`) and physical share breakdown; pre-fill deal details
  by scanning a printed receipt or a product barcode with on-device ML Kit
  recognition.
- **Reserve a slot** — students reserve or cancel a share in a deal, with the
  reserved/paid/collected counts kept live via Supabase Realtime.
- **Deal lifecycle** — a deal's status (open, paid, purchased, collected,
  cancelled) is derived from participant facts (who paid, who picked up)
  rather than stored directly, and the host has explicit controls to mark a
  deal paid, bought, collected, or cancelled.
- **Pickup checklist** — a per-participant checklist for confirming who has
  collected their share.
- **Notifications** — realtime, in-app reminders and status updates for deals
  a student is part of.
- **Profile & history** — a student's past deals and hub memberships in one
  view.
- **Reporting** — flag a deal or a specific participant for moderation.

## Tech stack

- **Flutter** (Dart) with the **provider** package for MVVM-style state
  management (screen + `ChangeNotifier` view model + repository per feature).
- **Supabase** (Postgres, Auth, Realtime) as the backend; see `supabase/migrations`
  for the schema and `lib/data/repositories` for the client-side gateways.
- **google_mlkit_text_recognition** / **google_mlkit_barcode_scanning** for
  on-device receipt and barcode scanning, plus **image_picker** to capture or
  select the source image.
- **geolocator** for hub discovery by distance.

## Project structure

```
lib/
  config/            Supabase environment configuration
  data/
    repositories/    One repository per domain (auth, hub, deal, reservation,
                      notification, recommendation, report)
    services/        Device-facing services (location, receipt/barcode scanning)
  models/            Domain models (Deal, Hub, Reservation, CostSplit, ...)
  ui/
    auth/            Sign in / sign up
    hub/              Create/join hub screens
    split_board/       Deal feed, deal creation, deal details, recommendations
    notifications/     Notification list
    profile/           Profile and deal history
    shared/             Shared theme, banners, form sections, message states
  utils/              Small pure helpers (geo distance, etc.)
supabase/migrations/  SQL migrations that define the backend schema
test/                 Unit and widget tests mirroring the lib/ layout
```

## Supabase setup

1. Copy `.env.example` to `.env`.
2. Add the project URL and publishable/anonymous key from your Supabase project:

   ```dotenv
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-publishable-or-anon-key
   ```

3. Enable Email authentication in Supabase. Configure email confirmation to
   match the desired signup flow.
4. Before production, configure Supabase Auth to use your own SMTP provider
   instead of the built-in mailer. The built-in mailer is acceptable for local
   development only.
5. Apply the SQL migrations in `supabase/migrations` (in order) to your
   Supabase project.
6. Run `flutter pub get`, then `flutter run`.

The local `.env` file is ignored by Git. The Supabase publishable/anonymous key
is intended for client applications; never place the service-role key in this
app.

## Frontend design

The interface uses Material 3 with semantic light and dark color roles defined
in `lib/ui/shared/app_theme.dart`. Manrope is bundled for body copy and controls,
while Outfit is bundled for screen and section headings, so typography does not
depend on a network request.

New screens and states should:

- use `Theme.of(context).colorScheme` instead of feature-specific colors;
- reuse the shared banners, form sections, icon containers, message states, and
  deal action bar where they match the interaction;
- keep search guidance inside search fields and retain visible text for
  important actions;
- support 320 logical-pixel viewports, 200% text scaling, and touch targets of
  at least 44 logical pixels;
- preserve the existing repositories, view models, routes, and business rules.

Run `flutter analyze` and `flutter test` before submitting frontend changes.
