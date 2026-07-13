import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/ui/split_board/widgets/deal_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('deal card displays stubbed deal details', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DealCard(
            deal: Deal(
              id: 'rice',
              hubId: 'colon',
              title: '25kg Rice Sack',
              // P900 over 5 slots is the 'P180/share' the card should render.
              totalPrice: 900,
              quantity: 1,
              category: DealCategory.grocery,
              availableSlots: 3,
              totalSlots: 5,
              pickupLocation: 'USJR Main Gate',
              status: DealStatus.open,
            ),
          ),
        ),
      ),
    );

    expect(find.text('25kg Rice Sack'), findsOneWidget);
    expect(find.text('P180/share'), findsOneWidget);
    expect(find.text('3 of 5 slots open'), findsOneWidget);
    expect(find.text('USJR Main Gate'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });
}
