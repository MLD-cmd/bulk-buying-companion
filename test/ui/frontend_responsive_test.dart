import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/hub/widgets/hub_card.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:bulk_buying_companion/ui/split_board/widgets/deal_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
          closesAt: DateTime(2026, 7, 18, 16),
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
