import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/widgets/deal_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('deal card displays stubbed deal details', (tester) async {
    await pumpCard(
      tester,
      deal: dealWith(
        id: 'rice',
        title: '25kg Rice Sack',
        totalPrice: 900,
        amount: 25,
        availableSlots: 3,
        totalSlots: 5,
        pickupLocation: 'USJR Main Gate',
      ),
    );

    expect(find.text('25kg Rice Sack'), findsOneWidget);
    expect(find.text('P180/share'), findsOneWidget);
    expect(find.text('3 of 5 slots open'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.byKey(const Key('deal-card-price')), findsOneWidget);
    expect(find.byKey(const Key('deal-card-physical-share')), findsOneWidget);
  });

  testWidgets('shows what each student physically gets, not just the price', (
    tester,
  ) async {
    await pumpCard(
      tester,
      deal: dealWith(
        id: 'water',
        title: 'Bottled Water Case',
        totalPrice: 380,
        amount: 24,
        unit: DealUnit.bottles,
        category: DealCategory.drinks,
        availableSlots: 2,
        totalSlots: 4,
        pickupLocation: 'Colon Street Hub',
      ),
    );

    expect(find.text('P95/share'), findsOneWidget);
    expect(find.text('6 bottles each'), findsOneWidget);
  });

  testWidgets('a full deal says Full, not Open', (tester) async {
    await pumpCard(
      tester,
      deal: dealWith(totalSlots: 4, availableSlots: 0, paidCount: 1),
    );

    expect(find.text('Full'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('a nearly full deal says Filling fast', (tester) async {
    await pumpCard(
      tester,
      deal: dealWith(totalSlots: 8, availableSlots: 2, paidCount: 1),
    );

    expect(find.text('Filling fast'), findsOneWidget);
  });

  testWidgets('a bought deal says Ready for pickup', (tester) async {
    await pumpCard(
      tester,
      deal: dealWith(
        totalSlots: 4,
        availableSlots: 0,
        paidCount: 4,
        purchasedAt: DateTime(2026, 7, 16),
      ),
    );

    expect(find.text('Ready for pickup'), findsOneWidget);
  });
}

Future<void> pumpCard(WidgetTester tester, {required Deal deal}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DealCard(deal: deal)),
    ),
  );
}

Deal dealWith({
  String id = 'd',
  String title = 'Rice',
  DealCategory category = DealCategory.grocery,
  double totalPrice = 400,
  double amount = 20,
  DealUnit unit = DealUnit.kg,
  required int availableSlots,
  required int totalSlots,
  int paidCount = 0,
  int collectedCount = 0,
  DateTime? purchasedAt,
  DateTime? cancelledAt,
  String pickupLocation = 'Campus Gate',
}) {
  return Deal(
    id: id,
    hubId: 'colon',
    title: title,
    totalPrice: totalPrice,
    amount: amount,
    unit: unit,
    category: category,
    availableSlots: availableSlots,
    totalSlots: totalSlots,
    pickupLocation: pickupLocation,
    paidCount: paidCount,
    collectedCount: collectedCount,
    purchasedAt: purchasedAt,
    cancelledAt: cancelledAt,
  );
}
