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
4. Run `flutter pub get`, then `flutter run`.

The local `.env` file is ignored by Git. The Supabase publishable/anonymous key
is intended for client applications; never place the service-role key in this
app.
