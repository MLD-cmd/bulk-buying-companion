# Supabase Authentication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Connect registration, login, session restoration, and logout to Supabase while displaying clear validation, confirmation, network, and authentication messages.

**Architecture:** Keep `AuthRepository` as the application boundary and add `SupabaseAuthRepository` backed by an injectable auth gateway. Initialize Supabase from a local `.env` in production, while dependency-injecting `MockAuthRepository` in widget tests.

**Tech Stack:** Flutter, Dart, Provider, `supabase_flutter`, `flutter_dotenv`, `flutter_test`

---

### Task 1: Generalize authentication results and email validation

**Files:**
- Modify: `lib/data/repositories/auth_repository.dart`
- Modify: `test/data/repositories/auth_repository_test.dart`

**Step 1: Write failing tests**

Add tests proving `EmailValidator` accepts institutional and ordinary valid addresses, rejects malformed addresses, and that registration returns an `AuthRegistrationResult` indicating whether confirmation is required.

**Step 2: Run the focused test**

Run: `flutter test test/data/repositories/auth_repository_test.dart`

Expected: FAIL because the generalized validator and result type do not exist.

**Step 3: Implement the minimal contract changes**

Rename the school-specific validator to a general email validator, add `AuthRegistrationResult(user, requiresEmailConfirmation)`, update `AuthRepository.register`, and adapt `MockAuthRepository` to return an authenticated result.

**Step 4: Run the focused test**

Run: `flutter test test/data/repositories/auth_repository_test.dart`

Expected: PASS.

### Task 2: Add the Supabase repository adapter

**Files:**
- Create: `lib/data/repositories/supabase_auth_repository.dart`
- Create: `test/data/repositories/supabase_auth_repository_test.dart`
- Modify: `pubspec.yaml`

**Step 1: Add failing adapter tests**

Define a narrow injectable `SupabaseAuthGateway` used by the repository tests. Cover current-user mapping, auth-state mapping, `signInWithPassword`, sign-up metadata (`display_name`), confirmation-required results, sign-out, and common `AuthException` message/status-code mappings.

**Step 2: Run the focused test**

Run: `flutter test test/data/repositories/supabase_auth_repository_test.dart`

Expected: FAIL because the adapter is missing.

**Step 3: Add dependencies and implementation**

Add `supabase_flutter` and `flutter_dotenv`. Implement the gateway around `GoTrueClient`, map Supabase users to `AppUser`, translate expected auth/network errors into `AuthFailure`, and do not expose raw server details for unknown errors.

**Step 4: Fetch dependencies**

Run: `flutter pub get`

Expected: dependencies resolve and `pubspec.lock` updates.

**Step 5: Run adapter tests**

Run: `flutter test test/data/repositories/supabase_auth_repository_test.dart`

Expected: PASS.

### Task 3: Initialize Supabase safely from `.env`

**Files:**
- Modify: `.gitignore`
- Create: `.env.example`
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

**Step 1: Add a failing widget construction test**

Update widget setup to inject `MockAuthRepository`, proving the app can be built in tests without initializing Supabase or loading `.env`.

**Step 2: Run the widget test**

Run: `flutter test test/widget_test.dart`

Expected: FAIL until the app accepts a repository override.

**Step 3: Implement configuration and injection**

Ignore `.env`, provide `.env.example` containing empty `SUPABASE_URL` and `SUPABASE_ANON_KEY` keys, declare `.env` as a Flutter asset, load it in `main`, validate non-empty configuration with a clear startup error, initialize Supabase, and inject `SupabaseAuthRepository`. Add an optional `authRepository` argument to `BulkBuyingCompanionApp` for tests.

**Step 4: Run widget tests**

Run: `flutter test test/widget_test.dart`

Expected: existing authentication and hub tests run without network access.

### Task 4: Display confirmation and authentication messages

**Files:**
- Modify: `lib/ui/auth/auth_viewmodel.dart`
- Modify: `lib/ui/auth/auth_screen.dart`
- Modify: `test/ui/auth/auth_viewmodel_test.dart`
- Modify: `test/widget_test.dart`

**Step 1: Write failing tests**

Cover a confirmation-required registration result, clearing notices when switching mode/resubmitting, general email acceptance, Supabase error display, and accessible live-region rendering.

**Step 2: Run focused tests**

Run: `flutter test test/ui/auth/auth_viewmodel_test.dart test/widget_test.dart`

Expected: FAIL because success notices and generalized validation are missing.

**Step 3: Implement presentation state**

Add `noticeMessage` to `AuthViewModel`, set it when registration requires confirmation, clear stale messages at appropriate transitions, update field labels/help text to say `Email`, and render a success/notice banner alongside the existing error banner.

**Step 4: Re-run focused tests**

Run: `flutter test test/ui/auth/auth_viewmodel_test.dart test/widget_test.dart`

Expected: PASS.

### Task 5: Make logout failures visible

**Files:**
- Modify: `lib/ui/profile/profile_viewmodel.dart`
- Modify: `lib/ui/profile/profile_screen.dart`
- Create: `test/ui/profile/profile_viewmodel_test.dart`
- Modify: `test/widget_test.dart`

**Step 1: Write failing tests**

Cover successful logout, duplicate-tap prevention, `AuthFailure` display, generic failure fallback, disabled/loading logout UI, and route dismissal only after success.

**Step 2: Run focused tests**

Run: `flutter test test/ui/profile/profile_viewmodel_test.dart test/widget_test.dart`

Expected: FAIL because logout has no view state or error handling.

**Step 3: Implement logout state and UI**

Make `signOut` return success/failure, track `isSigningOut` and `errorMessage`, catch repository errors, render an accessible error banner, disable repeated logout taps, show progress, and pop the route only on success.

**Step 4: Re-run focused tests**

Run: `flutter test test/ui/profile/profile_viewmodel_test.dart test/widget_test.dart`

Expected: PASS.

### Task 6: Verify the complete feature

**Files:**
- Review all files above.

**Step 1: Format**

Run: `dart format lib test`

Expected: formatter completes successfully.

**Step 2: Analyze**

Run: `flutter analyze`

Expected: no issues.

**Step 3: Test**

Run: `flutter test`

Expected: all tests pass without contacting Supabase.

**Step 4: Review scope**

Run: `git diff --check` and `git status --short`, then inspect the scoped diff. Confirm the existing hub, generated registrant, Gradle, and unrelated lockfile changes are preserved and not accidentally overwritten.
