import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_screen.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpDetails(
    WidgetTester tester,
    Deal deal, {
    String currentUserId = 'visitor',
  }) async {
    // Tall enough that the whole scrollable body — including the reserve
    // button below the new participants list — renders onstage, so plain
    // `find.text` / `find.byKey` see it without a manual scroll.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => DealDetailsViewModel(
            deal: deal,
            currentUserId: currentUserId,
            reservationRepository: MockReservationRepository(
              deal: deal,
              currentUserId: currentUserId,
            ),
          ),
          child: const DealDetailsScreen(),
        ),
      ),
    );
    // Lets the ViewModel's initial participants load resolve before assertions.
    await tester.pump();
  }

  testWidgets('shows the product, host, cost, slots and pickup details', (
    tester,
  ) async {
    await pumpDetails(tester, _deal);

    // Product information.
    expect(find.text('25kg Rice Sack'), findsOneWidget);
    expect(find.text('Sinandomeng, from the Carbon market'), findsOneWidget);
    expect(find.text('Grocery'), findsOneWidget);
    expect(find.text('1 kg'), findsOneWidget);

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

  testWidgets('shows the whole buy on the pill, not a meaningless unit count', (
    tester,
  ) async {
    await pumpDetails(tester, _bulk);

    expect(find.text('24 bottles'), findsOneWidget);
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

  testWidgets('states the surplus when the split is uneven', (tester) async {
    await pumpDetails(tester, _uneven);

    expect(find.text('P128.58'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsOneWidget);
  });

  testWidgets('shows what a student receives, not just what they pay', (
    tester,
  ) async {
    await pumpDetails(tester, _uneven);

    // The whole buy — not "1 unit".
    expect(find.text('25 kg'), findsOneWidget);
    expect(find.byKey(const Key('detail-physical-share')), findsOneWidget);
    expect(find.text('3.57 kg'), findsOneWidget);
  });

  testWidgets('says nothing about surplus on an even split', (tester) async {
    await pumpDetails(tester, _deal);

    expect(find.text('P180'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsNothing);
  });

  testWidgets('a student can take a slot', (tester) async {
    await pumpDetails(tester, _reservableDeal, currentUserId: 'user-2');

    expect(find.text('Reserve a slot'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-reserve-button')));
    await tester.pumpAndSettle();

    expect(find.text('Cancel my slot'), findsOneWidget);
  });

  testWidgets('the host is shown holding a slot they cannot give up', (
    tester,
  ) async {
    await pumpDetails(tester, _reservableDeal, currentUserId: 'user-1');

    expect(find.byKey(const Key('detail-host-slot-note')), findsOneWidget);
    expect(find.text('Cancel my slot'), findsNothing);
  });

  testWidgets('lists who is in the buy', (tester) async {
    await pumpDetails(tester, _reservableDeal, currentUserId: 'user-2');

    final participants = find.byKey(const Key('detail-participants'));
    expect(participants, findsOneWidget);
    expect(
      find.descendant(of: participants, matching: find.text('Marco Villanueva')),
      findsOneWidget,
    );
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
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
  closesAt: DateTime(2026, 7, 16),
);

const _bulk = Deal(
  id: 'colon-water',
  hubId: 'colon',
  title: 'Bottled Water Case',
  hostName: 'Bea Alonzo',
  category: DealCategory.drinks,
  totalPrice: 380,
  amount: 24,
  unit: DealUnit.bottles,
  availableSlots: 2,
  totalSlots: 4,
  pickupLocation: 'Colon Street Hub',
);

/// A deal whose host has no profile row — the left join in deal_feed returns
/// the deal with a null host_name rather than dropping it.
const _hostless = Deal(
  id: 'orphan',
  hubId: 'colon',
  title: 'Cooking Oil 5L',
  category: DealCategory.pantry,
  totalPrice: 750,
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 5,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);

const _uneven = Deal(
  id: 'colon-rice-7',
  hubId: 'colon',
  title: '25kg Rice Sack',
  hostName: 'Marco Villanueva',
  category: DealCategory.grocery,
  totalPrice: 900,
  amount: 25,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 7,
  pickupLocation: 'USJR Main Gate',
);

const _full = Deal(
  id: 'colon-detergent',
  hubId: 'colon',
  title: 'Laundry Detergent 6L',
  hostName: 'Rey Mercado',
  category: DealCategory.household,
  totalPrice: 360,
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 0,
  totalSlots: 3,
  pickupLocation: 'Barangay Hall Lobby',
);

/// Used by the reservation tests: needs a real [createdBy] so the host rules
/// (already holds a slot, cannot cancel) actually engage.
const _reservableDeal = Deal(
  id: 'colon-rice-reservable',
  hubId: 'colon',
  title: '25kg Rice Sack',
  createdBy: 'user-1',
  hostName: 'Marco Villanueva',
  category: DealCategory.grocery,
  totalPrice: 900,
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);
