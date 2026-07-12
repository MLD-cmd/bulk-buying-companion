# Student Registration and Login Design

## Scope

Build an interactive authentication stub for the existing Flutter application. The feature covers registration, login, approved school-email validation, password validation, visible authentication errors, and logout. It intentionally does not add a remote service or persist credentials; `MockAuthRepository` remains the replaceable seam for a future Firebase or Supabase implementation.

## Experience and architecture

The app starts behind an `AuthGate` that listens to `AuthRepository.authStateChanges`. Signed-out users see one responsive authentication screen with a Login/Register segmented switcher. Registration asks for name, school email, password, and password confirmation. Login asks for school email and password. Both modes use labeled Material fields, password visibility controls, inline validation, a loading state, and a form-level error banner. A successful action signs the user into the mock repository and reveals the existing Join Hub experience.

The repository owns stub identity behavior and emits auth-state updates through a broadcast stream. It accepts `.edu` addresses and explicitly approved school domains such as `usjr.edu.ph`; passwords require at least eight characters with upper-case, lower-case, and numeric characters. Registration creates an in-memory user, while login accepts a documented demo account and any account registered during the current app session. Profile exposes Logout, which signs out and lets the root gate return to Login.

The feature follows the existing Provider/MVVM structure: repository logic is framework-independent, `AuthViewModel` holds form/action state, and widgets only render and forward interactions. Repository tests cover validation and state transitions. Widget tests cover screen switching, errors, successful authentication, and logout. Existing hub behavior remains unchanged after authentication.
