import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/auth_repository.dart';
import 'data/repositories/deal_repository.dart';
import 'data/repositories/hub_repository.dart';
import 'models/app_user.dart';
import 'ui/auth/auth_screen.dart';
import 'ui/hub/join_hub_screen.dart';
import 'ui/hub/join_hub_viewmodel.dart';
import 'ui/shared/app_theme.dart';

void main() {
  runApp(const BulkBuyingCompanionApp());
}

class BulkBuyingCompanionApp extends StatelessWidget {
  const BulkBuyingCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>(
          create: (_) => MockAuthRepository(),
          dispose: (_, repository) => repository.dispose(),
        ),
        Provider<HubRepository>(create: (_) => MockHubRepository()),
        Provider<DealRepository>(create: (_) => MockDealRepository()),
        ChangeNotifierProvider<JoinHubViewModel>(
          create: (context) => JoinHubViewModel(
            authRepository: context.read<AuthRepository>(),
            hubRepository: context.read<HubRepository>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Campus Split-Share',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AuthRepository>();
    return StreamBuilder<AppUser?>(
      stream: repository.authStateChanges,
      initialData: repository.currentUser,
      builder: (context, snapshot) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: snapshot.data == null
              ? const AuthScreen(key: ValueKey('auth-screen'))
              : const JoinHubScreen(key: ValueKey('join-hub-screen')),
        );
      },
    );
  }
}
