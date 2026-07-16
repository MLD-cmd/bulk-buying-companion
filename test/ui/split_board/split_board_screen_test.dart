import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_screen.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_viewmodel.dart';
import 'package:bulk_buying_companion/ui/shared/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('search field filters visible split board deals', (tester) async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const [
        _StubDeal(id: 'rice', title: 'Rice Sack'),
        _StubDeal(id: 'water', title: 'Water Case'),
      ]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
      ),
    );
    await tester.pump();

    final search = tester.widget<TextField>(
      find.byKey(const Key('board-search-field')),
    );
    expect(search.decoration?.hintText, 'Search by product name');
    expect(search.decoration?.labelText, isNull);
    expect(find.text('Rice Sack'), findsOneWidget);
    expect(find.text('Water Case'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'rice');
    await tester.pump();

    expect(find.text('Rice Sack'), findsOneWidget);
    expect(find.text('Water Case'), findsNothing);
  });

  testWidgets('narrow board exposes secondary choices through Filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const [
        _StubDeal(id: 'rice', title: 'Rice Sack'),
      ]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
      ),
    );
    await tester.pump();

    final filters = find.widgetWithText(OutlinedButton, 'Filters');
    expect(filters, findsOneWidget);
    await tester.tap(filters);
    await tester.pumpAndSettle();

    expect(find.text('Filter deals'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Sort by'), findsOneWidget);
  });

  testWidgets('board keeps a readable content width on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const [
        _StubDeal(id: 'rice', title: 'Rice Sack'),
      ]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const Key('board-search-field'))).width,
      lessThanOrEqualTo(760),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('board uses a custom lazy scroll feed for deal rows', (
    tester,
  ) async {
    final deals = List<Deal>.generate(
      40,
      (index) => _StubDeal(id: 'deal-$index', title: 'Deal $index'),
    );
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(deals),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
      ),
    );
    await tester.pump();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byKey(const Key('deal-card-deal-39')), findsNothing);
  });

  testWidgets('initial load failure uses a full retry state and recovers', (
    tester,
  ) async {
    final retryResponse = Completer<List<Deal>>();
    final repository = _SequencedDealRepository([
      () async => throw StateError('offline'),
      () => retryResponse.future,
    ]);
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await _pumpBoard(tester, viewModel);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load deals"), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.byType(AppBanner), findsNothing);
    expect(find.byKey(const Key('board-search-field')), findsNothing);

    final retryButton = find.widgetWithText(OutlinedButton, 'Try again');
    await tester.tap(retryButton);
    await tester.tap(retryButton);
    await tester.pump();

    expect(repository.getDealsCalls, 2);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(find.text('Trying again…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Trying again'), findsOneWidget);

    retryResponse.complete(const [_StubDeal(id: 'rice', title: 'Rice Sack')]);
    await tester.pumpAndSettle();

    expect(find.text('Rice Sack'), findsOneWidget);
    expect(find.text("Couldn't load deals"), findsNothing);
  });

  testWidgets('successful empty load is not rendered as a failure', (
    tester,
  ) async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const []),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await _pumpBoard(tester, viewModel);
    await tester.pumpAndSettle();

    expect(find.text('No deals yet in this hub'), findsOneWidget);
    expect(find.text("Couldn't load deals"), findsNothing);
  });

  testWidgets('provider disposal is safe during the initial board load', (
    tester,
  ) async {
    final initialResponse = Completer<List<Deal>>();
    await _pumpBoardLauncher(
      tester,
      _SequencedDealRepository([() => initialResponse.future]),
    );

    await tester.tap(find.text('Open board'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    initialResponse.complete(const [_StubDeal(id: 'late', title: 'Late deal')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Open board'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider disposal is safe during a board refresh', (
    tester,
  ) async {
    final refreshResponse = Completer<List<Deal>>();
    await _pumpBoardLauncher(
      tester,
      _SequencedDealRepository([
        () async => const [_StubDeal(id: 'rice', title: 'Rice Sack')],
        () => refreshResponse.future,
      ]),
    );

    await tester.tap(find.text('Open board'));
    await tester.pumpAndSettle();
    final boardContext = tester.element(find.byType(SplitBoardScreen));
    final refresh = boardContext.read<SplitBoardViewModel>().refresh();
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    refreshResponse.complete(const [
      _StubDeal(id: 'water', title: 'Water Case'),
    ]);
    await refresh;
    await tester.pump();

    expect(find.text('Open board'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed post refresh does not announce after leaving board', (
    tester,
  ) async {
    final refreshResponse = Completer<List<Deal>>();
    const published = _StubDeal(id: 'oil', title: 'Cooking Oil 5L');
    final repository = _SequencedDealRepository([
      () async => const [_StubDeal(id: 'rice', title: 'Rice Sack')],
      () => refreshResponse.future,
    ], createdDeal: published);
    await _pumpBoardLauncher(tester, repository);

    await tester.tap(find.text('Open board'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('post-deal-button')));
    await tester.pumpAndSettle();
    await _fillCreateDeal(tester);
    final submit = find.byKey(const Key('deal-submit-button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byType(SplitBoardScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    refreshResponse.complete(const [published]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Open board'), findsOneWidget);
    expect(
      find.text('Cooking Oil 5L is now on the Split Board.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached refresh failure keeps feed and shows busy retry banner', (
    tester,
  ) async {
    final retryResponse = Completer<List<Deal>>();
    final repository = _SequencedDealRepository([
      () async => const [_StubDeal(id: 'rice', title: 'Rice Sack')],
      () async => throw StateError('offline'),
      () => retryResponse.future,
    ]);
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await _pumpBoard(tester, viewModel);
    await tester.pumpAndSettle();

    await viewModel.refresh();
    await tester.pump();

    final bannerFinder = find.byKey(const Key('board-refresh-error'));
    expect(find.text('Rice Sack'), findsOneWidget);
    expect(bannerFinder, findsOneWidget);
    expect(
      find.text('Couldn’t refresh deals. Showing the deals already loaded.'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(bannerFinder).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('board-search-field'))).dy,
      ),
    );
    var banner = tester.widget<AppBanner>(bannerFinder);
    expect(banner.actionLabel, 'Try again');
    expect(banner.actionBusy, isFalse);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    banner = tester.widget<AppBanner>(bannerFinder);
    expect(banner.actionBusy, isTrue);
    expect(
      find.descendant(
        of: bannerFinder,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('Rice Sack'), findsOneWidget);

    retryResponse.complete(const [_StubDeal(id: 'water', title: 'Water Case')]);
    await tester.pumpAndSettle();

    expect(find.text('Water Case'), findsOneWidget);
    expect(find.text('Rice Sack'), findsNothing);
    expect(bannerFinder, findsNothing);
  });

  testWidgets(
    'search filters and scroll geometry survive a details round trip',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final deals = List<Deal>.generate(
        30,
        (index) => _StubDeal(
          id: 'deal-$index',
          title: 'Deal $index',
          totalPrice: 400 + index.toDouble(),
        ),
      );
      final targetDeal = deals[15];
      final viewModel = SplitBoardViewModel(
        dealRepository: _FakeDealRepository(deals),
        hubId: 'colon',
        hubName: 'Colon Street Hub',
      );
      viewModel.updateCategoryFilter(DealCategory.grocery);
      viewModel.updateStatusFilter(DealStatus.open);
      viewModel.updateSortOption(DealSortOption.price);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReservationRepository>(
              create: (_) => MockReservationRepository(
                deal: targetDeal,
                currentUserId: 'visitor',
              ),
            ),
            Provider<AuthRepository>(create: (_) => MockAuthRepository()),
            ChangeNotifierProvider.value(value: viewModel),
          ],
          child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('board-search-field')),
        'Deal',
      );
      await tester.pump();

      final boardScroll = find.byKey(
        const PageStorageKey<String>('board-scroll-view'),
      );
      expect(boardScroll, findsOneWidget);
      final boardScrollable = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      expect(boardScrollable, findsOneWidget);
      final targetCard = find.byKey(const Key('deal-card-deal-15'));
      await tester.scrollUntilVisible(
        targetCard,
        500,
        scrollable: boardScrollable,
      );
      final offsetBefore = tester
          .widget<CustomScrollView>(boardScroll)
          .controller!
          .offset;
      expect(tester.getTopLeft(targetCard).dy, greaterThanOrEqualTo(56));

      await _openDetails(tester, 'deal-15');
      await tester.pageBack();
      await tester.pumpAndSettle();

      final scrollViewAfter = tester.widget<CustomScrollView>(boardScroll);
      final offsetAfter = scrollViewAfter.controller!.offset;
      expect(offsetAfter, moreOrLessEquals(offsetBefore, epsilon: 0.1));
      expect(tester.getTopLeft(targetCard).dy, greaterThanOrEqualTo(56));
      expect(
        tester.getBottomRight(targetCard).dy,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );

      scrollViewAfter.controller!.jumpTo(0);
      await tester.pump();
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('board-search-field')),
      );
      expect(searchField.controller?.text, 'Deal');
      expect(find.widgetWithText(InputChip, 'Grocery'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Open'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Sort: Price'), findsOneWidget);
    },
  );

  testWidgets('tapping a deal opens its details', (tester) async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const [
        _StubDeal(id: 'rice', title: 'Rice Sack'),
      ]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    // DealDetailsScreen.route() reads these to build its ViewModel.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReservationRepository>(
            create: (_) => MockReservationRepository(
              deal: const _StubDeal(id: 'rice', title: 'Rice Sack'),
              currentUserId: 'visitor',
            ),
          ),
          Provider<AuthRepository>(create: (_) => MockAuthRepository()),
          ChangeNotifierProvider.value(value: viewModel),
        ],
        child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
      ),
    );
    await tester.pump();

    await _openDetails(tester, 'rice');

    expect(find.text('Deal details'), findsOneWidget);
    expect(find.byKey(const Key('detail-cost-per-slot')), findsOneWidget);
    expect(find.byKey(const Key('detail-host-name')), findsOneWidget);
    // Below the fold once the participants section was added; existence is
    // all this test cares about, so skip the onstage-only filter.
    expect(
      find.byKey(const Key('detail-reserve-button'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('details return cannot mutate a removed board route', (
    tester,
  ) async {
    const deal = _StubDeal(id: 'rice', title: 'Rice Sack');
    final authRepository = MockAuthRepository();
    await authRepository.signIn(
      email: 'student@usjr.edu.ph',
      password: 'Student123',
    );
    final viewModel = _TrackingSplitBoardViewModel(
      dealRepository: _FakeDealRepository(const [deal]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    final observer = _RouteTracker();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReservationRepository>(
            create: (_) => MockReservationRepository(
              deal: deal,
              currentUserId: authRepository.currentUser!.uid,
            ),
          ),
          Provider<AuthRepository>.value(value: authRepository),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChangeNotifierProvider<SplitBoardViewModel>.value(
                          value: viewModel,
                          child: const SplitBoardScreen(hubId: 'colon'),
                        ),
                  ),
                ),
                child: const Text('Open tracked board'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open tracked board'));
    await tester.pumpAndSettle();
    final boardRoute = observer.routes.last;

    await _openDetails(tester, 'rice');
    final reserve = find.byKey(const Key('detail-reserve-button'));
    await tester.ensureVisible(reserve);
    await tester.tap(reserve);
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.removeRoute(boardRoute);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Open tracked board'), findsOneWidget);
    expect(viewModel.replaceDealCalls, 0);
    expect(tester.takeException(), isNull);
    viewModel.dispose();
  });

  testWidgets('the board updates when details returns a new lifecycle state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const deal = Deal(
      id: 'rice',
      hubId: 'colon',
      title: 'Rice Sack',
      createdBy: 'demo-student',
      category: DealCategory.grocery,
      totalPrice: 400,
      amount: 1,
      unit: DealUnit.kg,
      availableSlots: 0,
      totalSlots: 2,
      pickupLocation: 'Campus Gate',
      paidCount: 2,
    );
    final authRepository = MockAuthRepository();
    await authRepository.signIn(
      email: 'student@usjr.edu.ph',
      password: 'Student123',
    );
    final reservationRepository = MockReservationRepository(
      deal: deal,
      currentUserId: 'demo-student',
    );
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const [deal]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReservationRepository>.value(value: reservationRepository),
          Provider<AuthRepository>.value(value: authRepository),
          ChangeNotifierProvider.value(value: viewModel),
        ],
        child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
      ),
    );
    await tester.pump();

    expect(find.text('Ready to purchase'), findsOneWidget);

    await _openDetails(tester, 'rice');
    final purchasedButton = find.byKey(
      const Key('detail-mark-purchased-button'),
    );
    await tester.ensureVisible(purchasedButton);
    await tester.tap(purchasedButton);
    await tester.pumpAndSettle();
    expect(find.text('Mark this deal as purchased?'), findsOneWidget);
    await tester.tap(find.text('I’ve bought it'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Ready for pickup'), findsOneWidget);
    expect(find.text('Ready to purchase'), findsNothing);
  });
}

Future<void> _pumpBoard(WidgetTester tester, SplitBoardViewModel viewModel) {
  return tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: viewModel,
      child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
    ),
  );
}

Future<void> _pumpBoardLauncher(
  WidgetTester tester,
  DealRepository dealRepository,
) {
  return tester.pumpWidget(
    Provider<DealRepository>.value(
      value: dealRepository,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(SplitBoardScreen.route('colon', 'Colon Street Hub')),
              child: const Text('Open board'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _fillCreateDeal(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('deal-title-field')),
    'Cooking Oil 5L',
  );
  await tester.enterText(
    find.byKey(const Key('deal-total-price-field')),
    '750',
  );
  await tester.enterText(find.byKey(const Key('deal-amount-field')), '10');
  await tester.enterText(find.byKey(const Key('deal-total-slots-field')), '5');
  await tester.enterText(
    find.byKey(const Key('deal-pickup-location-field')),
    'USJR Main Gate',
  );
  await tester.pump();
}

/// The board is the only way into the details screen, so the tap has to work.
Future<void> _openDetails(WidgetTester tester, String dealId) async {
  await tester.tap(find.byKey(Key('deal-card-$dealId')));
  await tester.pumpAndSettle();
}

class _StubDeal extends Deal {
  const _StubDeal({
    required super.id,
    required super.title,
    super.totalPrice = 400,
  }) : super(
         hubId: 'colon',
         // P400 over 4 slots renders as 'P100/share'.
         amount: 1,
         unit: DealUnit.kg,
         category: DealCategory.grocery,
         availableSlots: 1,
         totalSlots: 4,
         pickupLocation: 'Campus Gate',
       );
}

class _FakeDealRepository implements DealRepository {
  const _FakeDealRepository(this._deals);

  final List<Deal> _deals;

  @override
  Future<List<Deal>> getDeals(String hubId) async => _deals;

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw UnimplementedError();
  }
}

class _SequencedDealRepository implements DealRepository {
  _SequencedDealRepository(this._responses, {this.createdDeal});

  final List<Future<List<Deal>> Function()> _responses;
  final Deal? createdDeal;
  int getDealsCalls = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) {
    return _responses[getDealsCalls++]();
  }

  @override
  Future<Deal> createDeal(DealDraft draft) async {
    return createdDeal ?? (throw UnimplementedError());
  }
}

class _TrackingSplitBoardViewModel extends SplitBoardViewModel {
  _TrackingSplitBoardViewModel({
    required super.dealRepository,
    required super.hubId,
    required super.hubName,
  });

  int replaceDealCalls = 0;

  @override
  void replaceDeal(Deal deal) {
    replaceDealCalls++;
    super.replaceDeal(deal);
  }
}

class _RouteTracker extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    super.didRemove(route, previousRoute);
  }
}
