# Bulk Buying Companion

A Flutter application.

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
5. Run `flutter pub get`, then `flutter run`.

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
