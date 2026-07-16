import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/ui/profile/profile_screen.dart';
import 'package:bulk_buying_companion/ui/profile/profile_viewmodel.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('profile contains only supported identity and hub actions', (
    tester,
  ) async {
    final authRepository = MockAuthRepository();
    await authRepository.signIn(
      email: 'student@usjr.edu.ph',
      password: 'Student123',
    );
    final hubRepository = MockHubRepository();
    await hubRepository.joinHub(
      userId: authRepository.currentUser!.uid,
      hubId: 'colon',
    );
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: hubRepository,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-avatar')), findsOneWidget);
    expect(find.text('CURRENT HUB'), findsOneWidget);
    expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Verified student'), findsNothing);
  });
}
