# Supabase Authentication Design

## Scope

Replace the app's in-memory production authentication with Supabase email/password authentication while retaining the repository seam and mock implementation for tests. Registration accepts any syntactically valid email address, including institutional addresses. The feature covers persistent sessions, registration metadata, email-confirmation feedback, logout, configuration validation, and readable authentication errors.

## Architecture and data flow

The app loads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from a gitignored `.env` before calling `runApp`. `Supabase.initialize` creates the production client, and `SupabaseAuthRepository` adapts `SupabaseClient.auth` to the existing `AuthRepository` contract. `BulkBuyingCompanionApp` accepts an optional repository override so widget tests can continue using `MockAuthRepository` without loading environment variables or contacting the network.

`SupabaseAuthRepository.currentUser` maps the current Supabase user into the existing `AppUser` model. The mapping uses the user ID, email, and `display_name` metadata written during sign-up. Its auth stream maps Supabase auth events into `AppUser?`, allowing `AuthGate` to restore persisted sessions, react to successful authentication, and return to login after logout.

Registration returns a result that distinguishes an authenticated session from a confirmation-required signup. When Supabase creates no session, `AuthViewModel` remains on the authentication screen and displays a success notice asking the user to check their email. Login and registration failures are normalized at the repository boundary into concise `AuthFailure` messages. The view model retains a generic fallback for unexpected failures.

Logout remains available from Profile. `ProfileViewModel` exposes submitting and error state, prevents duplicate requests, and only closes the profile route after Supabase confirms sign-out. A failed logout remains on Profile and displays an accessible error banner.

## Validation and testing

Client-side email validation checks general email syntax rather than requiring `.edu`. Existing password strength and password-confirmation validation remain. Repository tests exercise mapping, success states, confirmation-required registration, error translation, and logout through a small injectable Supabase-auth gateway. View-model and widget tests use fakes/mocks and never require real credentials. Final verification includes formatting, static analysis, the full Flutter test suite, and scoped diff review to preserve unrelated working-tree changes.
