import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_screen.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_viewmodel.dart';
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

    expect(find.text('Rice Sack'), findsOneWidget);
    expect(find.text('Water Case'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'rice');
    await tester.pump();

    expect(find.text('Rice Sack'), findsOneWidget);
    expect(find.text('Water Case'), findsNothing);
  });

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
}

/// The board is the only way into the details screen, so the tap has to work.
Future<void> _openDetails(WidgetTester tester, String dealId) async {
  await tester.tap(find.byKey(Key('deal-card-$dealId')));
  await tester.pumpAndSettle();
}

class _StubDeal extends Deal {
  const _StubDeal({required super.id, required super.title})
    : super(
        hubId: 'colon',
        // P400 over 4 slots renders as 'P100/share'.
        totalPrice: 400,
        amount: 1,
        unit: DealUnit.kg,
        category: DealCategory.grocery,
        availableSlots: 1,
        totalSlots: 4,
        pickupLocation: 'Campus Gate',
        status: DealStatus.open,
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
