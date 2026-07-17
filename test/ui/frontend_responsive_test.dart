import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/services/location_service.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/hub/create_hub_screen.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_screen.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_viewmodel.dart';
import 'package:bulk_buying_companion/ui/hub/widgets/hub_card.dart';
import 'package:bulk_buying_companion/ui/shared/app_icon_container.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:bulk_buying_companion/ui/split_board/create_deal_screen.dart';
import 'package:bulk_buying_companion/ui/split_board/widgets/deal_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('deal cards reflow at 320 pixels with 200 percent text', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      DealCard(
        deal: Deal(
          id: 'rice',
          hubId: 'colon',
          title: 'Premium long-grain rice sack for the campus cooperative',
          category: DealCategory.grocery,
          totalPrice: 925,
          amount: 25,
          unit: DealUnit.kg,
          availableSlots: 3,
          totalSlots: 7,
          pickupLocation: 'University main gate',
          // Relative: a fixed date passes and quietly changes what the card
          // renders, which is what this test is measuring.
          closesAt: DateTime.now().add(const Duration(days: 30)),
        ),
      ),
    );

    expect(find.byKey(const Key('deal-card-price')), findsOneWidget);
    expect(find.byKey(const Key('deal-card-physical-share')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub cards keep their action usable with enlarged text', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      HubCard(
        hub: const Hub(
          id: 'colon-campus',
          name: 'Colon Campus Student Cooperative Hub',
          type: HubType.areaHub,
          memberCount: 128,
          distanceLabel: '1.4 km away',
        ),
        isJoined: false,
        isPendingSwitch: false,
        showSwitchAction: false,
        onJoin: () {},
        onRequestSwitch: () {},
        onConfirmSwitch: () {},
        onCancelSwitch: () {},
      ),
    );

    expect(find.byKey(const Key('hub-join-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub cards keep compact actions inline on a normal phone', (
    tester,
  ) async {
    await _pumpPhone(
      tester,
      HubCard(
        hub: const Hub(
          id: 'colon-campus',
          name: 'Colon Campus Hub',
          type: HubType.areaHub,
          memberCount: 128,
          distanceLabel: '1.4 km away',
        ),
        isJoined: false,
        isPendingSwitch: false,
        showSwitchAction: false,
        onJoin: () {},
        onRequestSwitch: () {},
        onConfirmSwitch: () {},
        onCancelSwitch: () {},
      ),
    );

    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(HubCard))).scale(1),
      1,
    );
    expect(tester.getSize(find.byKey(const Key('hub-join-button'))).height, 48);
    final actionCenter = tester.getCenter(
      find.byKey(const Key('hub-join-button')),
    );
    final iconCenter = tester.getCenter(find.byType(AppIconContainer));
    expect((actionCenter.dy - iconCenter.dy).abs(), lessThan(45));
    expect(tester.takeException(), isNull);
  });

  testWidgets('current hub shares a compact row on Pixel 8 landscape', (
    tester,
  ) async {
    await _pumpCurrentHubScreen(tester, size: const Size(915, 412));

    final identity = find.byKey(const Key('current-hub-identity'));
    final actions = find.byKey(const Key('current-hub-actions'));
    expect(identity, findsOneWidget);
    expect(actions, findsOneWidget);
    expect(
      (tester.getCenter(identity).dy - tester.getCenter(actions).dy).abs(),
      lessThan(8),
    );
    expect(
      tester.getTopLeft(actions).dx,
      greaterThan(tester.getTopLeft(identity).dx),
    );
    expect(find.text('View deals'), findsOneWidget);
    expect(find.text('Leave hub'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current hub stacks at 320 pixels with 200 percent text', (
    tester,
  ) async {
    await _pumpCurrentHubScreen(
      tester,
      size: const Size(320, 1000),
      textScale: 2,
    );

    final identity = find.byKey(const Key('current-hub-identity'));
    final actions = find.byKey(const Key('current-hub-actions'));
    expect(
      tester.getTopLeft(actions).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(identity).dy),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'View deals')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Leave hub')).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short high-text hub screen scrolls past membership recovery into cards',
    (tester) async {
      final repository = _ResponsiveHubRepository(
        currentHubId: 'magallanes',
        failJoin: true,
      );
      final viewModel = await _pumpCurrentHubScreen(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        hubRepository: repository,
      );
      viewModel.requestSwitch('burgos');
      await viewModel.confirmSwitch();
      await tester.pumpAndSettle();

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(tester.takeException(), isNull);
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Try again'),
        120,
        scrollable: scrollable,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byKey(const Key('hub-search-field')),
        120,
        scrollable: scrollable,
      );
      expect(find.byKey(const Key('hub-nearby-filter')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('P. Burgos Boarding House'),
        160,
        scrollable: scrollable,
      );
      final burgosCard = find.ancestor(
        of: find.text('P. Burgos Boarding House'),
        matching: find.byType(HubCard),
      );
      final switchAction = find.descendant(
        of: burgosCard,
        matching: find.text('Switch'),
      );
      await tester.ensureVisible(switchAction);
      await tester.pumpAndSettle();
      await tester.tap(switchAction);
      await tester.pump();

      expect(
        find.descendant(of: burgosCard, matching: find.text('Confirm switch')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Post Deal stays usable at 320 pixels with 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      Provider<DealRepository>.value(
        value: MockDealRepository(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(CreateDealScreen.route('colon', 'Colon Street Hub')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final help = find.byTooltip('How to post a deal');
    expect(tester.getSize(help).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
    expect(find.byKey(const Key('deal-unit-field')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('deal-unit-field')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('deal-submit-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Register Hub stacks coordinates and protects details at 320 pixels with 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<HubRepository>.value(value: _ResponsiveHubRepository()),
            Provider<LocationService>.value(
              value: const _ResponsiveLocationStub(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(CreateHubScreen.route()),
                  child: const Text('open registration'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open registration'));
      await tester.pumpAndSettle();

      final latitude = find.byKey(const Key('hub-latitude-field'));
      final longitude = find.byKey(const Key('hub-longitude-field'));
      await tester.ensureVisible(latitude);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(longitude).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(latitude).dy),
      );
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byKey(const Key('hub-name-field')),
        'New campus hub',
      );
      FocusScope.of(tester.element(find.byType(CreateHubScreen))).unfocus();
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Discard these details?'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed hub and form screens support the complete viewport matrix at 200 percent',
    (tester) async {
      for (final size in _responsiveViewports) {
        await _pumpCurrentHubScreen(tester, size: size, textScale: 2);

        final hubHelp = find.byKey(const Key('hub-help-button-semantics'));
        final viewDeals = find.widgetWithText(TextButton, 'View deals');
        final leaveHub = find.widgetWithText(TextButton, 'Leave hub');
        expect(
          tester.getSemantics(hubHelp).label,
          'How to find and join a hub',
          reason: 'hub help is not labelled at $size',
        );
        expect(
          tester.getSize(viewDeals).height,
          greaterThanOrEqualTo(48),
          reason: 'View deals is too small at $size',
        );
        expect(
          tester.getSize(leaveHub).height,
          greaterThanOrEqualTo(48),
          reason: 'Leave hub is too small at $size',
        );
        expect(tester.takeException(), isNull, reason: 'hub overflow at $size');

        await _pumpPostDealAt(tester, size: size, textScale: 2);
        final dealHelp = find.widgetWithIcon(IconButton, Icons.help_outline);
        final unit = find.byKey(const Key('deal-unit-field'));
        expect(
          find.bySemanticsLabel('How to post a deal'),
          findsOneWidget,
          reason: 'Post Deal help is not labelled at $size',
        );
        expect(
          tester.getSize(dealHelp).shortestSide,
          greaterThanOrEqualTo(48),
          reason: 'Post Deal help is too small at $size',
        );
        expect(
          '${tester.getSemantics(unit).label} '
          '${tester.getSemantics(unit).value}',
          contains('Kilograms'),
          reason: 'selected unit is not announced at $size',
        );
        await tester.ensureVisible(find.byKey(const Key('deal-submit-button')));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('deal-submit-button'))).height,
          greaterThanOrEqualTo(48),
          reason: 'Post Deal primary action is too small at $size',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Post Deal overflow at $size',
        );

        await _pumpRegisterHubAt(tester, size: size, textScale: 2);
        await tester.ensureVisible(find.byKey(const Key('hub-submit-button')));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('hub-submit-button'))).height,
          greaterThanOrEqualTo(48),
          reason: 'Register Hub primary action is too small at $size',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Register Hub overflow at $size',
        );
      }
    },
  );
}

Future<JoinHubViewModel> _pumpCurrentHubScreen(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  _ResponsiveHubRepository? hubRepository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final authRepository = MockAuthRepository();
  await authRepository.signIn(
    email: 'student@usjr.edu.ph',
    password: 'Student123',
  );
  final repository =
      hubRepository ?? _ResponsiveHubRepository(currentHubId: 'magallanes');
  final viewModel = JoinHubViewModel(
    authRepository: authRepository,
    hubRepository: repository,
    locationService: const _ResponsiveLocationStub(),
  );
  addTearDown(() {
    viewModel.dispose();
    authRepository.dispose();
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

class _ResponsiveLocationStub implements LocationService {
  const _ResponsiveLocationStub();

  @override
  Future<Coordinates> getCurrentPosition() async {
    return const Coordinates(latitude: 10.2954, longitude: 123.8969);
  }
}

class _ResponsiveHubRepository implements HubRepository {
  _ResponsiveHubRepository({this.currentHubId, this.failJoin = false});

  final MockHubRepository _delegate = MockHubRepository();
  String? currentHubId;
  bool failJoin;

  @override
  Future<List<Hub>> getHubs() => _delegate.getHubs();

  @override
  Future<String?> getCurrentHubId(String userId) async => currentHubId;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {
    if (failJoin) throw StateError('raw membership failure');
    currentHubId = hubId;
  }

  @override
  Future<void> leaveHub({required String userId}) async {
    currentHubId = null;
  }

  @override
  Future<Hub> createHub(HubDraft draft) => _delegate.createHub(draft);
}

Future<void> _pumpPhone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(411, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpNarrow(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPostDealAt(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(
    Provider<DealRepository>.value(
      value: MockDealRepository(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(CreateDealScreen.route('colon', 'Colon Street Hub')),
              child: const Text('open deal form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open deal form'));
  await tester.pumpAndSettle();
}

Future<void> _pumpRegisterHubAt(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<HubRepository>.value(value: _ResponsiveHubRepository()),
        Provider<LocationService>.value(value: const _ResponsiveLocationStub()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context).push(CreateHubScreen.route()),
              child: const Text('open hub form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open hub form'));
  await tester.pumpAndSettle();
}

const _responsiveViewports = <Size>[
  Size(320, 568),
  Size(412, 915),
  Size(915, 412),
  Size(1200, 900),
];
