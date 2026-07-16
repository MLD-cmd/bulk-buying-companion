import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/deal_repository.dart';
import 'data/repositories/hub_repository.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/reservation_repository.dart';
import 'data/repositories/supabase_auth_repository.dart';
import 'data/services/location_service.dart';
import 'models/app_user.dart';
import 'ui/auth/auth_screen.dart';
import 'ui/hub/join_hub_screen.dart';
import 'ui/hub/join_hub_viewmodel.dart';
import 'ui/shared/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final config = SupabaseConfig.fromEnvironment(dotenv.env);
  await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
  final client = Supabase.instance.client;
  final repository = SupabaseAuthRepository(
    gateway: GoTrueSupabaseAuthGateway(client.auth),
  );
  final hubRepository = SupabaseHubRepository(
    gateway: PostgrestSupabaseHubGateway(client),
  );
  final dealRepository = SupabaseDealRepository(
    gateway: PostgrestSupabaseDealGateway(client),
    // Read lazily: the student is not signed in yet when the app boots.
    currentUserId: () => client.auth.currentUser!.id,
  );
  final reservationRepository = SupabaseReservationRepository(
    gateway: PostgrestSupabaseReservationGateway(client),
  );
  runApp(
    BulkBuyingCompanionApp(
      authRepository: repository,
      hubRepository: hubRepository,
      dealRepository: dealRepository,
      reservationRepository: reservationRepository,
      notificationInvalidationSource: SupabaseNotificationInvalidationSource(
        client,
      ),
    ),
  );
}

class BulkBuyingCompanionApp extends StatelessWidget {
  const BulkBuyingCompanionApp({
    super.key,
    this.authRepository,
    this.hubRepository,
    this.dealRepository,
    this.reservationRepository,
    this.notificationInvalidationSource,
    this.locationService,
  });

  final AuthRepository? authRepository;
  final HubRepository? hubRepository;
  final DealRepository? dealRepository;
  final ReservationRepository? reservationRepository;
  final NotificationInvalidationSource? notificationInvalidationSource;
  final LocationService? locationService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>(
          create: (_) => authRepository ?? MockAuthRepository(),
          dispose: (_, repository) => repository.dispose(),
        ),
        Provider<HubRepository>(
          create: (_) => hubRepository ?? MockHubRepository(),
        ),
        Provider<DealRepository>(
          create: (_) => dealRepository ?? MockDealRepository(),
        ),
        Provider<ReservationRepository>(
          create: (_) {
            final repository = reservationRepository;
            // Unlike the other repositories there is no sensible app-wide mock
            // here: a MockReservationRepository is built around one specific
            // deal. An app booting without a real one is a wiring bug, not
            // something to paper over with a fake.
            if (repository == null) {
              throw StateError('No ReservationRepository provided.');
            }
            return repository;
          },
        ),
        Provider<NotificationRepository>(
          create: (context) => DerivedNotificationRepository(
            dealRepository: context.read<DealRepository>(),
            reservationRepository: context.read<ReservationRepository>(),
            invalidationSource: notificationInvalidationSource,
          ),
        ),
        Provider<LocationService>(
          create: (_) => locationService ?? const GeolocatorLocationService(),
        ),
        ChangeNotifierProvider<JoinHubViewModel>(
          create: (context) => JoinHubViewModel(
            authRepository: context.read<AuthRepository>(),
            hubRepository: context.read<HubRepository>(),
            locationService: context.read<LocationService>(),
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
