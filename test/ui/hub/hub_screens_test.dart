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
}

class _LocationStub implements LocationService {
  const _LocationStub();

  @override
  Future<Coordinates> getCurrentPosition() async {
    return const Coordinates(latitude: 10.2954, longitude: 123.8969);
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
  final viewModel = JoinHubViewModel(
    authRepository: authRepository ?? _SignedInAuthRepository(),
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
    ChangeNotifierProvider.value(
      value: viewModel,
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
}

class _ControlledHubRepository implements HubRepository {
  _ControlledHubRepository({this.currentHubId});

  String? currentHubId;
  bool failDirectory = false;
  bool failJoin = false;
  bool failLeave = false;
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
  Future<Hub> createHub(HubDraft draft) => throw UnimplementedError();
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
