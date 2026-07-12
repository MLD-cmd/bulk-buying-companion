# Student Authentication Stub Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add interactive registration, login, validation, authentication errors, and logout using the app's in-memory auth seam.

**Architecture:** Extend `AuthRepository` with sign-in and registration operations, and make `MockAuthRepository` publish state changes. Add a Provider-backed auth view model and an app-level auth gate that switches between authentication and the existing hub UI.

**Tech Stack:** Flutter, Dart, Provider, Material 3, flutter_test

---

### Task 1: Define repository behavior

**Files:**
- Modify: `lib/data/repositories/auth_repository.dart`
- Create: `test/data/repositories/auth_repository_test.dart`

1. Write failing tests for approved email domains, password rules, registration state, login errors, and logout state.
2. Run `flutter test test/data/repositories/auth_repository_test.dart` and confirm failures are caused by missing APIs.
3. Add auth exceptions, validators, credential methods, and a broadcast state controller to the mock repository.
4. Re-run the focused repository test and confirm it passes.

### Task 2: Build the authentication presentation

**Files:**
- Create: `lib/ui/auth/auth_viewmodel.dart`
- Create: `lib/ui/auth/auth_screen.dart`
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

1. Replace the old signed-in-first widget assumptions with failing tests for the login screen, register mode, inline errors, and successful demo login.
2. Run `flutter test test/widget_test.dart` and confirm the new tests fail because the auth gate does not exist.
3. Implement `AuthViewModel`, responsive forms, mode switching, password visibility controls, error banner, and the root `AuthGate`.
4. Re-run widget tests and confirm the auth interactions and existing hub interactions pass.

### Task 3: Add logout

**Files:**
- Modify: `lib/ui/profile/profile_viewmodel.dart`
- Modify: `lib/ui/profile/profile_screen.dart`
- Modify: `test/widget_test.dart`

1. Write a failing widget test that signs in, opens Profile, taps Logout, and expects Login.
2. Run the focused widget test and verify it fails for the missing action.
3. Add a view-model logout method and an accessible destructive ListTile/button on Profile.
4. Re-run the widget test and confirm the auth gate returns to Login.

### Task 4: Verify the feature

**Files:**
- Review all files above.

1. Run `dart format lib test`.
2. Run `flutter analyze`.
3. Run `flutter test`.
4. Inspect `git diff --check`, `git status --short`, and the scoped diff to ensure unrelated user changes were preserved.
