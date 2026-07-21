import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/deal_repository.dart';
import 'data/repositories/hub_repository.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/recommendation_repository.dart';
import 'data/repositories/reservation_repository.dart';
import 'data/repositories/report_repository.dart';
import 'data/repositories/supabase_auth_repository.dart';
import 'data/services/location_service.dart';
import 'data/services/receipt_scanner.dart';
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
    invalidationSource: SupabaseHubInvalidationSource(client),
  );
  final dealRepository = SupabaseDealRepository(
    gateway: PostgrestSupabaseDealGateway(client),
    // Read lazily: the student is not signed in yet when the app boots.
    currentUserId: () => client.auth.currentUser!.id,
    invalidationSource: SupabaseDealInvalidationSource(client),
  );
  final reservationRepository = SupabaseReservationRepository(
    gateway: PostgrestSupabaseReservationGateway(client),
    invalidationSource: SupabaseReservationInvalidationSource(client),
  );
  final reportRepository = SupabaseReportRepository(
    gateway: PostgrestSupabaseReportGateway(client),
    currentUserId: () => client.auth.currentUser!.id,
    invalidationSource: SupabaseReportInvalidationSource(client),
  );
  final recommendationRepository = SupabaseRecommendationRepository(
    gateway: PostgrestSupabaseRecommendationGateway(client),
  );
  runApp(
    BulkBuyingCompanionApp(
      authRepository: repository,
      hubRepository: hubRepository,
      dealRepository: dealRepository,
      reservationRepository: reservationRepository,
      reportRepository: reportRepository,
      recommendationRepository: recommendationRepository,
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
    this.reportRepository,
    this.recommendationRepository,
    this.notificationInvalidationSource,
    this.locationService,
    this.receiptScanner,
    this.showStartupSplash = true,
  });

  final AuthRepository? authRepository;
  final HubRepository? hubRepository;
  final DealRepository? dealRepository;
  final ReservationRepository? reservationRepository;
  final ReportRepository? reportRepository;
  final RecommendationRepository? recommendationRepository;
  final NotificationInvalidationSource? notificationInvalidationSource;
  final LocationService? locationService;
  final ReceiptScanner? receiptScanner;
  final bool showStartupSplash;

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
        Provider<ReportRepository>(
          create: (_) => reportRepository ?? MockReportRepository(),
        ),
        Provider<RecommendationRepository>(
          create: (_) =>
              recommendationRepository ?? MockRecommendationRepository(),
          dispose: (_, repository) => repository.dispose(),
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
        Provider<ReceiptScanner>(
          create: (_) => receiptScanner ?? MlKitReceiptScanner(),
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
        scrollBehavior: const AppScrollBehavior(),
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: showStartupSplash
            ? const StartupSplashGate()
            : const AuthGate(key: ValueKey('auth-gate')),
      ),
    );
  }
}

class StartupSplashGate extends StatefulWidget {
  const StartupSplashGate({super.key});

  @override
  State<StartupSplashGate> createState() => _StartupSplashGateState();
}

class _StartupSplashGateState extends State<StartupSplashGate> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: _showSplash
          ? const AppSplashScreen(key: ValueKey('startup-splash'))
          : const AuthGate(key: ValueKey('auth-gate')),
    );
  }
}

class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      key: const Key('app-splash-screen'),
      backgroundColor: const Color(0xFFEAF7F5),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/branding/splash_logo.png',
                width: 132,
                height: 132,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 22),
              Text(
                'Campus Split-Share',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bulk buys, split fairly.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
