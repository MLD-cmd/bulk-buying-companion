import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
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
}

class _StubDeal extends Deal {
  const _StubDeal({required super.id, required super.title})
    : super(
        hubId: 'colon',
        // P400 over 4 slots renders as 'P100/share'.
        totalPrice: 400,
        quantity: 1,
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
