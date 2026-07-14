import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDetails(WidgetTester tester, Deal deal) {
    return tester.pumpWidget(MaterialApp(home: DealDetailsScreen(deal: deal)));
  }

  testWidgets('shows the product, host, cost, slots and pickup details', (
    tester,
  ) async {
    await pumpDetails(tester, _deal);

    // Product information.
    expect(find.text('25kg Rice Sack'), findsOneWidget);
    expect(find.text('Sinandomeng, from the Carbon market'), findsOneWidget);
    expect(find.text('Grocery'), findsOneWidget);
    expect(find.text('1 unit'), findsOneWidget);

    // Host information.
    expect(find.text('Marco Villanueva'), findsOneWidget);

    // Cost per slot: P900 split 5 ways.
    expect(find.text('P180'), findsOneWidget);
    expect(find.text('Total P900'), findsOneWidget);
    expect(find.text('split 5 ways'), findsOneWidget);

    // Available slots.
    expect(find.text('3 of 5 slots open'), findsOneWidget);
    expect(find.text('2 of 5 already claimed'), findsOneWidget);

    // Pickup details.
    expect(find.text('USJR Main Gate'), findsOneWidget);
    expect(find.text('Closes 7/16/2026'), findsOneWidget);

    // Reservation button.
    expect(find.text('Reserve a slot'), findsOneWidget);
  });

  testWidgets('pluralises the unit count', (tester) async {
    await pumpDetails(tester, _bulk);

    expect(find.text('24 units'), findsOneWidget);
  });

  testWidgets('names a host with no profile rather than leaving a gap', (
    tester,
  ) async {
    await pumpDetails(tester, _hostless);

    expect(find.text('A student in this hub'), findsOneWidget);
  });

  testWidgets('omits the description when there is none', (tester) async {
    await pumpDetails(tester, _hostless);

    expect(find.byKey(const Key('detail-description')), findsNothing);
  });

  testWidgets('disables reserving once the deal is full', (tester) async {
    await pumpDetails(tester, _full);

    expect(find.text('No slots left'), findsOneWidget);
    expect(find.text('0 of 3 slots open'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('detail-reserve-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('reserving is not wired up yet and says so', (tester) async {
    await pumpDetails(tester, _deal);

    final button = find.byKey(const Key('detail-reserve-button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(find.text('Reserving a slot is coming soon.'), findsOneWidget);
  });

  testWidgets('states the surplus when the split is uneven', (tester) async {
    await pumpDetails(tester, _uneven);

    expect(find.text('P128.58'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsOneWidget);
  });

  testWidgets('says nothing about surplus on an even split', (tester) async {
    await pumpDetails(tester, _deal);

    expect(find.text('P180'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsNothing);
  });
}

final _deal = Deal(
  id: 'colon-rice',
  hubId: 'colon',
  title: '25kg Rice Sack',
  description: 'Sinandomeng, from the Carbon market',
  hostName: 'Marco Villanueva',
  category: DealCategory.grocery,
  totalPrice: 900,
  quantity: 1,
  availableSlots: 3,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
  status: DealStatus.open,
  closesAt: DateTime(2026, 7, 16),
);

const _bulk = Deal(
  id: 'colon-water',
  hubId: 'colon',
  title: 'Bottled Water Case',
  hostName: 'Bea Alonzo',
  category: DealCategory.drinks,
  totalPrice: 380,
  quantity: 24,
  availableSlots: 2,
  totalSlots: 4,
  pickupLocation: 'Colon Street Hub',
  status: DealStatus.fillingFast,
);

/// A deal whose host has no profile row — the left join in deal_feed returns
/// the deal with a null host_name rather than dropping it.
const _hostless = Deal(
  id: 'orphan',
  hubId: 'colon',
  title: 'Cooking Oil 5L',
  category: DealCategory.pantry,
  totalPrice: 750,
  quantity: 1,
  availableSlots: 5,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
  status: DealStatus.open,
);

const _uneven = Deal(
  id: 'colon-rice-7',
  hubId: 'colon',
  title: '25kg Rice Sack',
  hostName: 'Marco Villanueva',
  category: DealCategory.grocery,
  totalPrice: 900,
  quantity: 1,
  availableSlots: 3,
  totalSlots: 7,
  pickupLocation: 'USJR Main Gate',
  status: DealStatus.open,
);

const _full = Deal(
  id: 'colon-detergent',
  hubId: 'colon',
  title: 'Laundry Detergent 6L',
  hostName: 'Rey Mercado',
  category: DealCategory.household,
  totalPrice: 360,
  quantity: 1,
  availableSlots: 0,
  totalSlots: 3,
  pickupLocation: 'Barangay Hall Lobby',
  status: DealStatus.full,
);
