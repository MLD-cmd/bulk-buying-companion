import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/repositories/notification_repository.dart';
import 'package:bulk_buying_companion/data/services/location_service.dart';
import 'package:bulk_buying_companion/models/deal_notification.dart';
import 'package:bulk_buying_companion/ui/hub/create_hub_screen.dart';
import 'package:bulk_buying_companion/ui/hub/create_hub_viewmodel.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_screen.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_viewmodel.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('hub search guidance stays inside the search field', (
    tester,
  ) async {
    final authRepository = MockAuthRepository();
    await authRepository.signIn(
      email: 'student@usjr.edu.ph',
      password: 'Student123',
    );
    final viewModel = JoinHubViewModel(
      authRepository: authRepository,
      hubRepository: MockHubRepository(),
      locationService: const _LocationStub(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const JoinHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(
      find.byKey(const Key('hub-search-field')),
    );
    expect(search.decoration?.hintText, 'Search hubs, buildings, areas…');
    expect(search.decoration?.labelText, isNull);
  });

  testWidgets('hub registration centers location and keeps coordinates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = CreateHubViewModel(
      hubRepository: MockHubRepository(),
      locationService: const _LocationStub(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CreateHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('hub-use-location-button')),
    );
    expect(button.style?.alignment, Alignment.center);
    expect(find.byKey(const Key('hub-latitude-field')), findsOneWidget);
    expect(find.byKey(const Key('hub-longitude-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current hub exposes notifications', (tester) async {
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
    final viewModel = JoinHubViewModel(
      authRepository: authRepository,
      hubRepository: hubRepository,
      locationService: const _LocationStub(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthRepository>.value(value: authRepository),
          Provider<NotificationRepository>.value(
            value: const _NotificationStub([]),
          ),
          ChangeNotifierProvider.value(value: viewModel),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const JoinHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('notification bell shows an unread indicator count', (
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
    final viewModel = JoinHubViewModel(
      authRepository: authRepository,
      hubRepository: hubRepository,
      locationService: const _LocationStub(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthRepository>.value(value: authRepository),
          Provider<NotificationRepository>.value(
            value: const _NotificationStub([
              DealNotification(
                id: 'deal-1-payment',
                dealId: 'deal-1',
                kind: DealNotificationKind.paymentReminder,
                title: 'Payment reminder',
                message: 'Pay P100 for Rice.',
              ),
            ]),
          ),
          ChangeNotifierProvider.value(value: viewModel),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const JoinHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-badge')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('new realtime notifications show a popup', (tester) async {
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
    final viewModel = JoinHubViewModel(
      authRepository: authRepository,
      hubRepository: hubRepository,
      locationService: const _LocationStub(),
    );
    final notifications = StreamController<List<DealNotification>>();
    addTearDown(viewModel.dispose);
    addTearDown(notifications.close);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AuthRepository>.value(value: authRepository),
          Provider<NotificationRepository>.value(
            value: _StreamingNotificationStub(notifications.stream),
          ),
          ChangeNotifierProvider.value(value: viewModel),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const JoinHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifications.add(const []);
    await tester.pump();
    expect(find.text('Payment reminder'), findsNothing);

    notifications.add(const [
      DealNotification(
        id: 'deal-1-payment',
        dealId: 'deal-1',
        kind: DealNotificationKind.paymentReminder,
        title: 'Payment reminder',
        message: 'Pay P100 for Rice.',
      ),
    ]);
    await tester.pump();

    expect(find.text('Payment reminder'), findsOneWidget);
    expect(find.text('Pay P100 for Rice.'), findsOneWidget);
  });
}

class _LocationStub implements LocationService {
  const _LocationStub();

  @override
  Future<Coordinates> getCurrentPosition() async {
    return const Coordinates(latitude: 10.2954, longitude: 123.8969);
  }
}

class _NotificationStub implements NotificationRepository {
  const _NotificationStub(this.notifications);

  final List<DealNotification> notifications;

  @override
  Future<List<DealNotification>> getNotifications({
    required String hubId,
    required String currentUserId,
  }) async {
    return notifications;
  }

  @override
  Stream<List<DealNotification>> watchNotifications({
    required String hubId,
    required String currentUserId,
  }) {
    return Stream.value(notifications);
  }
}

class _StreamingNotificationStub implements NotificationRepository {
  const _StreamingNotificationStub(this.stream);

  final Stream<List<DealNotification>> stream;

  @override
  Future<List<DealNotification>> getNotifications({
    required String hubId,
    required String currentUserId,
  }) async {
    return const [];
  }

  @override
  Stream<List<DealNotification>> watchNotifications({
    required String hubId,
    required String currentUserId,
  }) {
    return stream;
  }
}
