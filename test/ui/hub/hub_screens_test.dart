import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/services/location_service.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/hub/create_hub_screen.dart';
import 'package:bulk_buying_companion/ui/hub/create_hub_viewmodel.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_screen.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_viewmodel.dart';
import 'package:bulk_buying_companion/ui/hub/widgets/hub_card.dart';
import 'package:bulk_buying_companion/ui/shared/app_message_state.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bulk_buying_companion/data/repositories/notification_repository.dart';
import 'package:bulk_buying_companion/models/deal_notification.dart';

void main() {
  testWidgets(
    'initial directory failure is a retryable error instead of an empty state',
    (tester) async {
      final repository = _ControlledHubRepository()..failDirectory = true;
      final viewModel = await _pumpJoinHubScreen(
        tester,
        repository: repository,
      );

      expect(find.byType(AppMessageState), findsOneWidget);
      expect(find.text('Couldn’t load hubs'), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(find.text('No hubs yet'), findsNothing);
      expect(find.byKey(const Key('hub-search-field')), findsNothing);

      repository.failDirectory = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(viewModel.directoryErrorMessage, isNull);
      expect(find.text('Couldn’t load hubs'), findsNothing);
      expect(find.text('Magallanes Residence'), findsOneWidget);
    },
  );

  testWidgets(
    'failed refresh retains discovery controls and retries cached directory',
    (tester) async {
      final repository = _ControlledHubRepository();
      final viewModel = await _pumpJoinHubScreen(
        tester,
        repository: repository,
      );

      await tester.enterText(find.byKey(const Key('hub-search-field')), 'hub');
      await tester.tap(find.byKey(const Key('hub-nearby-filter')));
      await tester.pump();
      expect(viewModel.searchQuery, 'hub');
      expect(viewModel.nearbyOnly, isTrue);

      repository.failDirectory = true;
      await viewModel.refresh();
      await tester.pump();

      expect(find.byKey(const Key('hub-search-field')), findsOneWidget);
      expect(find.byKey(const Key('hub-nearby-filter')), findsOneWidget);
      expect(find.byType(HubCard), findsNWidgets(2));
      expect(
        find.text('Couldn’t load hubs. Check your connection and try again.'),
        findsOneWidget,
      );

      repository.failDirectory = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(viewModel.directoryErrorMessage, isNull);
      expect(viewModel.searchQuery, 'hub');
      expect(viewModel.nearbyOnly, isTrue);
      expect(
        find.text('Couldn’t load hubs. Check your connection and try again.'),
        findsNothing,
      );
      expect(find.byType(HubCard), findsNWidgets(2));
    },
  );

  testWidgets(
    'membership failure explains the consequence and retry updates its target',
    (tester) async {
      final repository = _ControlledHubRepository()..failJoin = true;
      final viewModel = await _pumpJoinHubScreen(
        tester,
        repository: repository,
      );

      await tester.tap(_hubAction('Magallanes Residence', 'Join'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Couldn’t join this hub. Your current hub has not changed. '
          'Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(viewModel.joinedHubId, isNull);

      repository.failJoin = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(viewModel.membershipErrorMessage, isNull);
      expect(viewModel.joinedHubId, 'magallanes');
      expect(repository.joinedHubIds, ['magallanes', 'magallanes']);
      expect(
        find.descendant(
          of: _hubCard('Magallanes Residence'),
          matching: find.text('Joined'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('location failure retry restores distance discovery', (
    tester,
  ) async {
    final location = _ControlledLocationService(
      failure: const LocationFailure('Location permission denied.'),
    );
    final viewModel = await _pumpJoinHubScreen(
      tester,
      repository: _ControlledHubRepository(),
      locationService: location,
    );

    expect(find.text('Location permission denied.'), findsOneWidget);
    expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);
    expect(find.byKey(const Key('hub-nearby-filter')), findsNothing);

    location
      ..failure = null
      ..result = const Coordinates(latitude: 10.2954, longitude: 123.8969);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(location.calls, 2);
    expect(viewModel.locationFailureMessage, isNull);
    expect(find.text('Location permission denied.'), findsNothing);
    expect(find.byKey(const Key('hub-nearby-filter')), findsOneWidget);
  });

  testWidgets(
    'only the joining hub announces progress while other joins stay disabled',
    (tester) async {
      final repository = _ControlledHubRepository()..blockNextJoin();
      await _pumpJoinHubScreen(tester, repository: repository);

      await tester.tap(_hubAction('Magallanes Residence', 'Join'));
      await tester.pump();

      expect(find.text('Joining…'), findsOneWidget);
      expect(find.text('Switching…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.descendant(
          of: _hubCard('North Area Hub'),
          matching: find.text('Join'),
        ),
        findsOneWidget,
      );
      expect(_buttonFor(tester, 'North Area Hub', 'Join').onPressed, isNull);

      repository.releaseJoin();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('inline switch confirmation drives targeted switching progress', (
    tester,
  ) async {
    final repository = _ControlledHubRepository(currentHubId: 'magallanes');
    await _pumpJoinHubScreen(tester, repository: repository);

    await tester.tap(_hubAction('North Area Hub', 'Switch'));
    await tester.pump();

    expect(
      find.descendant(
        of: _hubCard('North Area Hub'),
        matching: find.text('Confirm switch'),
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);

    repository.blockNextJoin();
    await tester.tap(_hubAction('North Area Hub', 'Confirm switch'));
    await tester.pump();

    expect(find.text('Switching…'), findsOneWidget);
    final switching = find.widgetWithText(OutlinedButton, 'Switching…');
    expect(tester.getSemantics(switching).label, contains('Switching'));
    expect(tester.getSize(switching).height, greaterThanOrEqualTo(48));
    expect(find.text('Joining…'), findsNothing);
    expect(_buttonFor(tester, 'South Campus Hub', 'Switch').onPressed, isNull);
    expect(
      find.descendant(
        of: _hubCard('South Campus Hub'),
        matching: find.text('Switching…'),
      ),
      findsNothing,
    );

    repository.releaseJoin();
    await tester.pumpAndSettle();
    expect(repository.joinedHubIds, ['north']);
  });

  testWidgets('leave confirms exact consequences before showing progress', (
    tester,
  ) async {
    final repository = _ControlledHubRepository(currentHubId: 'magallanes');
    final viewModel = await _pumpJoinHubScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(TextButton, 'Leave hub'));
    await tester.pumpAndSettle();

    expect(repository.leaveCalls, 0);
    expect(find.text('Leave Magallanes Residence?'), findsOneWidget);
    expect(
      find.text(
        'You’ll need to join a hub again before you can open its Split Board.',
      ),
      findsOneWidget,
    );
    expect(find.text('Stay'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Leave hub'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(repository.leaveCalls, 0);
    expect(viewModel.joinedHubId, 'magallanes');

    repository.blockNextLeave();
    await tester.tap(find.widgetWithText(TextButton, 'Leave hub'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Leave hub'),
      ),
    );
    await tester.pump();

    expect(repository.leaveCalls, 1);
    expect(find.text('Leaving…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final leaving = find.widgetWithText(TextButton, 'Leaving…');
    expect(tester.getSemantics(leaving).label, contains('Leaving'));
    expect(tester.getSize(leaving).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'View deals'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Leaving…'))
          .onPressed,
      isNull,
    );

    repository.releaseLeave();
    await tester.pumpAndSettle();
    expect(viewModel.joinedHubId, isNull);
  });

  testWidgets('stale View deals callback does not navigate after auth clears', (
    tester,
  ) async {
    final authRepository = _ControlledAuthRepository(
      initialUser: const AppUser(
        uid: 'student-1',
        eduEmail: 'student@example.com',
      ),
    );
    addTearDown(authRepository.dispose);
    await _pumpJoinHubScreen(
      tester,
      repository: _ControlledHubRepository(currentHubId: 'magallanes'),
      authRepository: authRepository,
    );
    final screenContext = tester.element(find.byType(JoinHubScreen));
    final staleCallback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'View deals'))
        .onPressed!;

    authRepository.emit(null);
    await tester.pumpAndSettle();

    expect(Navigator.of(screenContext).canPop(), isFalse);
    expect(staleCallback, returnsNormally);
    expect(Navigator.of(screenContext).canPop(), isFalse);
  });

  testWidgets('leave confirmation cannot act after membership changes', (
    tester,
  ) async {
    final repository = _ControlledHubRepository(currentHubId: 'magallanes');
    final viewModel = await _pumpJoinHubScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(TextButton, 'Leave hub'));
    await tester.pumpAndSettle();
    await viewModel.join('north');
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Leave hub'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.leaveCalls, 0);
    expect(viewModel.joinedHubId, 'north');
    expect(find.text('Leave North Area Hub?'), findsNothing);
  });

  testWidgets('repeated leave activation opens one dialog and leaves once', (
    tester,
  ) async {
    final repository = _ControlledHubRepository(currentHubId: 'magallanes');
    await _pumpJoinHubScreen(tester, repository: repository);
    final leaveAction = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Leave hub'))
        .onPressed!;

    leaveAction();
    leaveAction();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Leave hub'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    expect(repository.leaveCalls, 1);
  });

  testWidgets('hub help is concise and preserves discovery state', (
    tester,
  ) async {
    final viewModel = await _pumpJoinHubScreen(
      tester,
      repository: _ControlledHubRepository(),
    );
    await tester.enterText(find.byKey(const Key('hub-search-field')), 'hub');
    await tester.tap(find.byKey(const Key('hub-nearby-filter')));
    await tester.pump();

    final helpTooltip = find.byTooltip('How to find and join a hub');
    final helpButton = find.widgetWithIcon(IconButton, Icons.help_outline);
    final helpSemantics = find.byKey(const Key('hub-help-button-semantics'));
    expect(helpTooltip, findsOneWidget);
    expect(helpButton, findsOneWidget);
    expect(tester.getSize(helpButton).shortestSide, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(helpSemantics).label,
      'How to find and join a hub',
    );

    await tester.tap(helpButton);
    await tester.pumpAndSettle();

    expect(find.text('Search or use distance'), findsOneWidget);
    expect(find.text('Review type and details'), findsOneWidget);
    expect(find.text('Join or switch'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(
      find.byKey(const Key('hub-search-field')),
    );
    final nearby = tester.widget<FilterChip>(
      find.byKey(const Key('hub-nearby-filter')),
    );
    expect(search.controller?.text, 'hub');
    expect(nearby.selected, isTrue);
    expect(viewModel.searchQuery, 'hub');
    expect(viewModel.nearbyOnly, isTrue);
    expect(
      Navigator.of(tester.element(find.byType(JoinHubScreen))).canPop(),
      isFalse,
    );
  });

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

  testWidgets('untouched registration Back leaves without confirmation', (
    tester,
  ) async {
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: const _LocationStub(),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Register a hub'), findsNothing);
    expect(find.text('Discard these details?'), findsNothing);
  });

  testWidgets('Keep editing preserves all changed registration details', (
    tester,
  ) async {
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: const _LocationStub(),
    );
    await tester.enterText(
      find.byKey(const Key('hub-name-field')),
      'Sanciangko Apartments',
    );
    await tester.tap(find.text('Area hub'));
    await tester.enterText(
      find.byKey(const Key('hub-latitude-field')),
      '10.300001',
    );
    await tester.enterText(
      find.byKey(const Key('hub-longitude-field')),
      '123.900001',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard these details?'), findsOneWidget);
    expect(
      find.text('Your unpublished hub details will be lost if you leave now.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(
      _hubTextField(tester, const Key('hub-name-field')).controller?.text,
      'Sanciangko Apartments',
    );
    expect(
      _hubTextField(tester, const Key('hub-latitude-field')).controller?.text,
      '10.300001',
    );
    expect(
      _hubTextField(tester, const Key('hub-longitude-field')).controller?.text,
      '123.900001',
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('hub-type-areaHub')))
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('name, type, and coordinate changes each protect registration', (
    tester,
  ) async {
    final edits = <Future<void> Function()>[
      () =>
          tester.enterText(find.byKey(const Key('hub-name-field')), 'New hub'),
      () => tester.tap(find.text('Area hub')),
      () =>
          tester.enterText(find.byKey(const Key('hub-latitude-field')), '10.3'),
      () => tester.enterText(
        find.byKey(const Key('hub-longitude-field')),
        '123.9',
      ),
    ];

    for (final edit in edits) {
      await _pumpCreateHubRoute(
        tester,
        repository: _CreateHubRepository(),
        locationService: const _LocationStub(),
      );
      await edit();
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard these details?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('successful location capture protects populated coordinates', (
    tester,
  ) async {
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: const _LocationStub(),
    );

    await tester.tap(find.byKey(const Key('hub-use-location-button')));
    await tester.pumpAndSettle();

    expect(
      _hubTextField(tester, const Key('hub-latitude-field')).controller?.text,
      '10.295400',
    );
    expect(
      _hubTextField(tester, const Key('hub-longitude-field')).controller?.text,
      '123.896900',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('Discard leaves registration once and dialogs do not stack', (
    tester,
  ) async {
    final observer = _HubRouteObserver();
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: const _LocationStub(),
      observer: observer,
    );
    await tester.enterText(find.byKey(const Key('hub-name-field')), 'New hub');

    final guard = tester.widget<PopScope<Hub>>(find.byType(PopScope<Hub>));
    guard.onPopInvokedWithResult?.call(false, null);
    guard.onPopInvokedWithResult?.call(false, null);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Register a hub'), findsNothing);
    expect(observer.hubRoutePops, 1);
  });

  testWidgets(
    'invalid untouched submit focuses first error without latching dirty',
    (tester) async {
      await _pumpCreateHubRoute(
        tester,
        repository: _CreateHubRepository(),
        locationService: const _LocationStub(),
      );

      final fields = <Key>[
        const Key('hub-name-field'),
        const Key('hub-latitude-field'),
        const Key('hub-longitude-field'),
      ];
      final actions = <TextInputAction>[
        TextInputAction.next,
        TextInputAction.next,
        TextInputAction.done,
      ];
      for (var index = 0; index < fields.length; index++) {
        expect(
          _hubTextField(tester, fields[index]).textInputAction,
          actions[index],
        );
      }

      await tester.tap(find.byKey(fields.first));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(_hubTextField(tester, fields[1]).focusNode?.hasFocus, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(_hubTextField(tester, fields[2]).focusNode?.hasFocus, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(_hubTextField(tester, fields[2]).focusNode?.hasFocus, isFalse);

      await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
      await tester.tap(find.byKey(const Key('hub-submit-button')));
      await tester.pumpAndSettle();
      expect(_hubTextField(tester, fields.first).focusNode?.hasFocus, isTrue);
      FocusScope.of(tester.element(find.byType(CreateHubScreen))).unfocus();
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Register a hub'), findsNothing);
      expect(find.text('Discard these details?'), findsNothing);
    },
  );

  testWidgets('fully reverted registration details leave without a guard', (
    tester,
  ) async {
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: const _LocationStub(),
    );
    await tester.enterText(
      find.byKey(const Key('hub-name-field')),
      'Temporary hub',
    );
    await tester.enterText(find.byKey(const Key('hub-latitude-field')), '10.3');
    await tester.enterText(
      find.byKey(const Key('hub-longitude-field')),
      '123.9',
    );
    final areaType = find.byKey(const Key('hub-type-areaHub'));
    await tester.ensureVisible(areaType);
    await tester.tap(areaType);
    await tester.pump();

    await tester.enterText(find.byKey(const Key('hub-name-field')), '');
    await tester.enterText(find.byKey(const Key('hub-latitude-field')), '');
    await tester.enterText(find.byKey(const Key('hub-longitude-field')), '');
    final dormitoryType = find.byKey(const Key('hub-type-dormitory'));
    await tester.ensureVisible(dormitoryType);
    await tester.pumpAndSettle();
    await tester.tap(dormitoryType);
    FocusScope.of(tester.element(find.byType(CreateHubScreen))).unfocus();
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Register a hub'), findsNothing);
    expect(find.text('Discard these details?'), findsNothing);
  });

  testWidgets('registration failure keeps changed details protected', (
    tester,
  ) async {
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(
        failure: const HubFailure('Could not register this hub.'),
      ),
      locationService: const _LocationStub(),
    );
    await _fillCreateHubForm(tester);

    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Could not register this hub.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('successful registration returns its typed Hub without a guard', (
    tester,
  ) async {
    late Future<Hub?> routeResult;
    final repository = _CreateHubRepository();
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: const _LocationStub(),
      onRoutePushed: (result) => routeResult = result,
    );
    await _fillCreateHubForm(tester);

    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();

    final result = await routeResult;
    expect(result?.name, 'Sanciangko Apartments');
    expect(find.text('Register a hub'), findsNothing);
    expect(find.text('Discard these details?'), findsNothing);
  });

  testWidgets('Back and stale actions cannot interrupt location capture', (
    tester,
  ) async {
    final locationService = _DelayedCreateLocationService();
    final repository = _CreateHubRepository();
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: locationService,
    );
    final staleLocation = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('hub-use-location-button')),
        )
        .onPressed!;
    final staleSubmit = tester
        .widget<FilledButton>(find.byKey(const Key('hub-submit-button')))
        .onPressed!;
    final staleNameChange = _hubTextField(
      tester,
      const Key('hub-name-field'),
    ).onChanged!;
    final staleType = tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(const Key('hub-type-areaHub')),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!;

    staleLocation();
    await tester.pump();
    _expectCreateHubControlsEnabled(tester, false);
    staleLocation();
    staleSubmit();
    staleNameChange('Stale name');
    staleType();
    await tester.pageBack();
    await tester.pump();

    expect(locationService.calls, 1);
    expect(repository.createCalls, 0);
    expect(find.text('Register a hub'), findsOneWidget);
    expect(find.text('Discard these details?'), findsNothing);
    expect(
      _hubTextField(tester, const Key('hub-name-field')).controller?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('hub-type-dormitory')))
          .properties
          .selected,
      isTrue,
    );

    locationService.complete(
      const Coordinates(latitude: 10.31, longitude: 123.91),
    );
    await tester.pumpAndSettle();
    _expectCreateHubControlsEnabled(tester, true);
    expect(
      _hubTextField(tester, const Key('hub-latitude-field')).controller?.text,
      '10.310000',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('location failure unlocks controls without stale changes', (
    tester,
  ) async {
    final locationService = _DelayedCreateLocationService();
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: locationService,
    );
    final staleNameChange = _hubTextField(
      tester,
      const Key('hub-name-field'),
    ).onChanged!;
    final staleType = tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(const Key('hub-type-areaHub')),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!;

    await tester.tap(find.byKey(const Key('hub-use-location-button')));
    await tester.pump();
    _expectCreateHubControlsEnabled(tester, false);
    staleNameChange('Stale name');
    staleType();

    locationService.fail(const LocationFailure('Location permission denied.'));
    await tester.pumpAndSettle();

    _expectCreateHubControlsEnabled(tester, true);
    expect(find.text('Location permission denied.'), findsOneWidget);
    expect(
      _hubTextField(tester, const Key('hub-name-field')).controller?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('hub-type-dormitory')))
          .properties
          .selected,
      isTrue,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Register a hub'), findsNothing);
    expect(find.text('Discard these details?'), findsNothing);
  });

  testWidgets('pending registration locks fields and cannot be discarded', (
    tester,
  ) async {
    late Future<Hub?> routeResult;
    final repository = _DelayedCreateHubRepository();
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: const _LocationStub(),
      onRoutePushed: (result) => routeResult = result,
    );
    await _fillCreateHubForm(tester);
    final areaType = find.byKey(const Key('hub-type-areaHub'));
    await tester.ensureVisible(areaType);
    await tester.tap(areaType);
    await tester.pump();
    final staleSubmit = tester
        .widget<FilledButton>(find.byKey(const Key('hub-submit-button')))
        .onPressed!;
    final staleType = tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text('Dormitory'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!;

    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pump();

    expect(repository.createCalls, 1);
    expect(repository.pendingDraft?.type, HubType.areaHub);
    expect(_hubTextField(tester, const Key('hub-name-field')).enabled, isFalse);
    expect(
      _hubTextField(tester, const Key('hub-latitude-field')).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('hub-use-location-button')),
          )
          .onPressed,
      isNull,
    );

    staleType();
    staleSubmit();
    await tester.pageBack();
    await tester.pump();
    expect(repository.createCalls, 1);
    expect(find.text('Register a hub'), findsOneWidget);
    expect(find.text('Discard these details?'), findsNothing);

    final created = repository.complete();
    await tester.pumpAndSettle();
    expect(await routeResult, same(created));
    expect(repository.pendingDraft?.type, HubType.areaHub);
    expect(find.text('Register a hub'), findsNothing);
  });

  testWidgets('delayed registration failure unlocks only after completion', (
    tester,
  ) async {
    final repository = _DelayedCreateHubRepository();
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: const _LocationStub(),
    );
    await _fillCreateHubForm(tester);

    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pump();
    await tester.pageBack();
    await tester.pump();

    expect(find.text('Register a hub'), findsOneWidget);
    expect(find.text('Discard these details?'), findsNothing);
    expect(_hubTextField(tester, const Key('hub-name-field')).enabled, isFalse);

    repository.fail(const HubFailure('Could not register this hub.'));
    await tester.pumpAndSettle();

    expect(find.text('Could not register this hub.'), findsOneWidget);
    expect(_hubTextField(tester, const Key('hub-name-field')).enabled, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('disposing an open registration guard has no stale callback', (
    tester,
  ) async {
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: const _LocationStub(),
    );
    await tester.enterText(
      find.byKey(const Key('hub-name-field')),
      'New campus hub',
    );
    FocusScope.of(tester.element(find.byType(CreateHubScreen))).unfocus();
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('immediate Back safely disposes a delayed directory load', (
    tester,
  ) async {
    final repository = _DelayedDirectoryCreateHubRepository();
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: const _LocationStub(),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Register a hub'), findsNothing);

    repository.completeDirectory();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ancestor teardown safely disposes delayed location capture', (
    tester,
  ) async {
    final locationService = _DelayedCreateLocationService();
    await _pumpCreateHubRoute(
      tester,
      repository: _CreateHubRepository(),
      locationService: locationService,
    );
    await tester.tap(find.byKey(const Key('hub-use-location-button')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    locationService.complete(
      const Coordinates(latitude: 10.31, longitude: 123.91),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('ancestor teardown safely disposes delayed registration', (
    tester,
  ) async {
    final repository = _DelayedCreateHubRepository();
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: const _LocationStub(),
    );
    await _fillCreateHubForm(tester);
    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    repository.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('hub discovery keeps a readable content width on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    expect(
      tester.getSize(find.byKey(const Key('hub-search-field'))).width,
      lessThanOrEqualTo(720),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a registered hub whose list reload fails is not called listed', (
    tester,
  ) async {
    final repository = _ControlledHubRepository();
    await _pumpJoinHubScreen(tester, repository: repository);

    await tester.tap(find.byTooltip('Register a hub'));
    await tester.pumpAndSettle();
    await _fillCreateHubForm(tester);

    // The hub itself saves; only the directory reload behind it goes down.
    repository.failDirectory = true;
    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(
      find.text(
        'Sanciangko Apartments was registered, but the hub list didn’t reload.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Sanciangko Apartments is now on the hub list.'),
      findsNothing,
    );
  });

  testWidgets('a registered hub that reloads cleanly is reported as listed', (
    tester,
  ) async {
    final repository = _ControlledHubRepository();
    await _pumpJoinHubScreen(tester, repository: repository);

    await tester.tap(find.byTooltip('Register a hub'));
    await tester.pumpAndSettle();
    await _fillCreateHubForm(tester);
    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Sanciangko Apartments is now on the hub list.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed hub directory says duplicate checking is degraded', (
    tester,
  ) async {
    await _pumpCreateHubRoute(
      tester,
      repository: _FailingDirectoryCreateHubRepository(),
      locationService: const _LocationStub(),
    );

    expect(
      find.byKey(const Key('hub-duplicate-check-warning')),
      findsOneWidget,
    );
    // Degraded, not blocked: the student can still register.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('hub-submit-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('retrying a failed hub directory restores duplicate checking', (
    tester,
  ) async {
    final repository = _FailingDirectoryCreateHubRepository(
      hubs: [
        const Hub(
          id: 'existing',
          name: 'Sanciangko Apartments',
          type: HubType.dormitory,
          memberCount: 4,
          distanceLabel: 'Nearby',
        ),
      ],
    );
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: const _LocationStub(),
    );
    expect(
      find.byKey(const Key('hub-duplicate-check-warning')),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hub-duplicate-check-warning')), findsNothing);

    // The recovered directory is actually used: this name is now a duplicate.
    await _fillCreateHubForm(tester);
    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('A hub named "Sanciangko Apartments" is already registered.'),
      findsOneWidget,
    );
    expect(repository.createCalls, 0);
  });

  testWidgets('a hub directory that never loads still registers the hub', (
    tester,
  ) async {
    final repository = _FailingDirectoryCreateHubRepository(failures: 99);
    await _pumpCreateHubRoute(
      tester,
      repository: repository,
      locationService: const _LocationStub(),
    );

    await _fillCreateHubForm(tester);
    await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
  });
}

class _LocationStub implements LocationService {
  const _LocationStub();

  @override
  Future<Coordinates> getCurrentPosition() async {
    return const Coordinates(latitude: 10.2954, longitude: 123.8969);
  }
}

TextField _hubTextField(WidgetTester tester, Key key) =>
    tester.widget<TextField>(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    );

void _expectCreateHubControlsEnabled(WidgetTester tester, bool enabled) {
  for (final key in const [
    Key('hub-name-field'),
    Key('hub-latitude-field'),
    Key('hub-longitude-field'),
  ]) {
    expect(_hubTextField(tester, key).enabled, enabled);
  }
  for (final key in const [
    Key('hub-type-dormitory'),
    Key('hub-type-areaHub'),
  ]) {
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      enabled ? isNotNull : isNull,
    );
  }
  expect(
    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('hub-use-location-button')),
        )
        .onPressed,
    enabled ? isNotNull : isNull,
  );
  expect(
    tester
        .widget<FilledButton>(find.byKey(const Key('hub-submit-button')))
        .onPressed,
    enabled ? isNotNull : isNull,
  );
}

Future<void> _fillCreateHubForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('hub-name-field')),
    'Sanciangko Apartments',
  );
  await tester.enterText(
    find.byKey(const Key('hub-latitude-field')),
    '10.4000',
  );
  await tester.enterText(
    find.byKey(const Key('hub-longitude-field')),
    '124.0000',
  );
  await tester.pump();
}

Future<void> _pumpCreateHubRoute(
  WidgetTester tester, {
  required HubRepository repository,
  required LocationService locationService,
  NavigatorObserver? observer,
  ValueChanged<Future<Hub?>>? onRoutePushed,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<HubRepository>.value(value: repository),
        Provider<LocationService>.value(value: locationService),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        navigatorObservers: observer == null ? const [] : [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                final result = Navigator.of(
                  context,
                ).push(CreateHubScreen.route());
                onRoutePushed?.call(result);
              },
              child: const Text('open registration'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open registration'));
  await tester.pumpAndSettle();
}

class _CreateHubRepository implements HubRepository {
  _CreateHubRepository({this.failure});

  final HubFailure? failure;
  int createCalls = 0;

  @override
  Future<List<Hub>> getHubs() async => const [];

  @override
  Future<Hub> createHub(HubDraft draft) async {
    createCalls += 1;
    final error = failure;
    if (error != null) throw error;
    return _hubFromDraft(draft);
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

/// Fails the directory read the first [failures] times, then serves [hubs].
class _FailingDirectoryCreateHubRepository implements HubRepository {
  _FailingDirectoryCreateHubRepository({
    this.failures = 1,
    this.hubs = const [],
  });

  final int failures;
  final List<Hub> hubs;
  int getHubsCalls = 0;
  int createCalls = 0;

  @override
  Future<List<Hub>> getHubs() async {
    getHubsCalls += 1;
    if (getHubsCalls <= failures) throw StateError('offline');
    return hubs;
  }

  @override
  Future<Hub> createHub(HubDraft draft) async {
    createCalls += 1;
    return _hubFromDraft(draft);
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _DelayedDirectoryCreateHubRepository implements HubRepository {
  final _directoryCompleter = Completer<List<Hub>>();

  void completeDirectory() => _directoryCompleter.complete(const []);

  @override
  Future<List<Hub>> getHubs() => _directoryCompleter.future;

  @override
  Future<Hub> createHub(HubDraft draft) async => _hubFromDraft(draft);

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _DelayedCreateHubRepository implements HubRepository {
  final _completer = Completer<Hub>();
  int createCalls = 0;
  HubDraft? pendingDraft;

  Hub complete() {
    final hub = _hubFromDraft(pendingDraft!);
    _completer.complete(hub);
    return hub;
  }

  void fail(Object error) => _completer.completeError(error);

  @override
  Future<List<Hub>> getHubs() async => const [];

  @override
  Future<Hub> createHub(HubDraft draft) {
    createCalls += 1;
    pendingDraft = draft;
    return _completer.future;
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _DelayedCreateLocationService implements LocationService {
  final _completer = Completer<Coordinates>();
  int calls = 0;

  void complete(Coordinates coordinates) => _completer.complete(coordinates);

  void fail(Object error) => _completer.completeError(error);

  @override
  Future<Coordinates> getCurrentPosition() {
    calls += 1;
    return _completer.future;
  }
}

Hub _hubFromDraft(HubDraft draft) => Hub(
  id: hubSlug(draft.name),
  name: draft.name.trim(),
  type: draft.type,
  memberCount: 0,
  distanceLabel: '',
  latitude: draft.latitude,
  longitude: draft.longitude,
);

class _HubRouteObserver extends NavigatorObserver {
  int hubRoutePops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == null && route is MaterialPageRoute<Hub>) {
      hubRoutePops += 1;
    }
    super.didPop(route, previousRoute);
  }
}

const _hubs = [
  Hub(
    id: 'magallanes',
    name: 'Magallanes Residence',
    type: HubType.dormitory,
    memberCount: 24,
    distanceLabel: 'Saved distance',
    latitude: 10.2954,
    longitude: 123.8969,
  ),
  Hub(
    id: 'north',
    name: 'North Area Hub',
    type: HubType.areaHub,
    memberCount: 18,
    distanceLabel: 'Saved distance',
    latitude: 10.2960,
    longitude: 123.8969,
  ),
  Hub(
    id: 'south',
    name: 'South Campus Hub',
    type: HubType.areaHub,
    memberCount: 12,
    distanceLabel: 'Saved distance',
    latitude: 10.2948,
    longitude: 123.8969,
  ),
];

Future<JoinHubViewModel> _pumpJoinHubScreen(
  WidgetTester tester, {
  required _ControlledHubRepository repository,
  AuthRepository? authRepository,
  LocationService? locationService,
}) async {
  final auth = authRepository ?? _SignedInAuthRepository();
  final viewModel = JoinHubViewModel(
    authRepository: auth,
    hubRepository: repository,
    locationService:
        locationService ??
        _ControlledLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
  );
  addTearDown(() {
    repository.releaseJoin();
    repository.releaseLeave();
    viewModel.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<JoinHubViewModel>.value(value: viewModel),
        // The Register-a-hub route builds its own CreateHubViewModel from these.
        Provider<HubRepository>.value(value: repository),
        // The notification bell in the app bar reads these.
        Provider<AuthRepository>.value(value: auth),
        Provider<NotificationRepository>.value(
          value: const _NotificationStub([]),
        ),
        Provider<LocationService>.value(
          value:
              locationService ??
              _ControlledLocationService(
                result: const Coordinates(
                  latitude: 10.2954,
                  longitude: 123.8969,
                ),
              ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const JoinHubScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return viewModel;
}

Finder _hubCard(String hubName) =>
    find.ancestor(of: find.text(hubName), matching: find.byType(HubCard));

Finder _hubAction(String hubName, String label) =>
    find.descendant(of: _hubCard(hubName), matching: find.text(label));

ButtonStyleButton _buttonFor(
  WidgetTester tester,
  String hubName,
  String label,
) {
  return tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: _hubAction(hubName, label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    ),
  );
}

class _SignedInAuthRepository implements AuthRepository {
  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  AppUser? get currentUser =>
      const AppUser(uid: 'student-1', eduEmail: 'student@example.com');

  @override
  Future<AppUser> signIn({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {}

  @override
  void dispose() {}

  @override
  Future<AppUser> updateDisplayName(String displayName) {
    throw UnimplementedError();
  }
}

class _ControlledAuthRepository implements AuthRepository {
  _ControlledAuthRepository({required AppUser? initialUser})
    : _currentUser = initialUser;

  final _controller = StreamController<AppUser?>.broadcast(sync: true);
  AppUser? _currentUser;

  void emit(AppUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<AppUser> signIn({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async => emit(null);

  @override
  void dispose() => _controller.close();

  @override
  Future<AppUser> updateDisplayName(String displayName) {
    throw UnimplementedError();
  }
}

class _ControlledHubRepository implements HubRepository {
  _ControlledHubRepository({this.currentHubId});

  String? currentHubId;
  bool failDirectory = false;
  bool failJoin = false;
  bool failLeave = false;
  int createCalls = 0;
  Completer<void>? _joinGate;
  Completer<void>? _leaveGate;
  final List<String> joinedHubIds = [];
  int leaveCalls = 0;

  void blockNextJoin() => _joinGate = Completer<void>();

  void releaseJoin() {
    final gate = _joinGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void blockNextLeave() => _leaveGate = Completer<void>();

  void releaseLeave() {
    final gate = _leaveGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<List<Hub>> getHubs() async {
    if (failDirectory) throw StateError('raw directory failure');
    return _hubs;
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => currentHubId;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {
    joinedHubIds.add(hubId);
    final gate = _joinGate;
    if (gate != null) await gate.future;
    if (failJoin) throw StateError('raw membership failure');
    currentHubId = hubId;
  }

  @override
  Future<void> leaveHub({required String userId}) async {
    leaveCalls += 1;
    final gate = _leaveGate;
    if (gate != null) await gate.future;
    if (failLeave) throw StateError('raw membership failure');
    currentHubId = null;
  }

  @override
  Future<Hub> createHub(HubDraft draft) async {
    createCalls += 1;
    return _hubFromDraft(draft);
  }
}

class _ControlledLocationService implements LocationService {
  _ControlledLocationService({this.result, this.failure});

  Coordinates? result;
  LocationFailure? failure;
  int calls = 0;

  @override
  Future<Coordinates> getCurrentPosition() async {
    calls += 1;
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    return result!;
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
