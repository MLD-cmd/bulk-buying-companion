import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_recommendation.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/widgets/recommended_deals_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Deal _deal(String id) => Deal(
  id: id,
  hubId: 'colon',
  title: 'Deal $id',
  category: DealCategory.grocery,
  totalPrice: 400,
  amount: 4,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 4,
  pickupLocation: 'Gate',
  createdBy: 'host',
  paidCount: 1,
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders a card and reason per recommendation', (tester) async {
    await tester.pumpWidget(
      _host(
        RecommendedDealsSection(
          recommendations: [
            DealRecommendation(
              deal: _deal('rice'),
              score: 20,
              reason: 'Matches your interest in Grocery',
            ),
          ],
          onOpenDeal: (_) {},
          onDismiss: (_) {},
        ),
      ),
    );

    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Deal rice'), findsOneWidget);
    expect(find.text('Matches your interest in Grocery'), findsOneWidget);
    expect(find.byKey(const Key('recommendation-card-rice')), findsOneWidget);
  });

  testWidgets('reports the dismissed deal', (tester) async {
    Deal? dismissed;
    await tester.pumpWidget(
      _host(
        RecommendedDealsSection(
          recommendations: [
            DealRecommendation(
              deal: _deal('rice'),
              score: 20,
              reason: 'Because',
            ),
          ],
          onOpenDeal: (_) {},
          onDismiss: (deal) => dismissed = deal,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('recommendation-dismiss-rice')));
    expect(dismissed?.id, 'rice');
  });

  testWidgets('renders nothing when there are no recommendations', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RecommendedDealsSection(
          recommendations: const [],
          onOpenDeal: (_) {},
          onDismiss: (_) {},
        ),
      ),
    );

    expect(find.text('Recommended for you'), findsNothing);
    expect(find.byKey(const Key('recommended-deals-section')), findsNothing);
  });
}
