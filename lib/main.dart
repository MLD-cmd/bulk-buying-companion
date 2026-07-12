import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/auth_repository.dart';
import 'data/repositories/hub_repository.dart';
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
        // JT: swap MockAuthRepository for the real Firebase/Supabase
        // implementation here once Student Registration & Login lands.
        // Everything below only depends on the AuthRepository interface.
        Provider<AuthRepository>(create: (_) => MockAuthRepository()),
        Provider<HubRepository>(create: (_) => MockHubRepository()),
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
        home: const JoinHubScreen(),
      ),
    );
  }
}
