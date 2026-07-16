import 'package:bulk_buying_companion/ui/shared/app_banner.dart';
import 'package:bulk_buying_companion/ui/shared/app_form_section.dart';
import 'package:bulk_buying_companion/ui/shared/app_icon_container.dart';
import 'package:bulk_buying_companion/ui/shared/app_message_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppBanner announces a live error message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppBanner.error(message: 'Could not load deals.')),
      ),
    );

    expect(find.text('Could not load deals.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(AppBanner)).flagsCollection.isLiveRegion,
      isTrue,
    );
  });

  testWidgets('AppMessageState exposes an optional retry action', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMessageState(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't load deals",
            message: 'Check your connection and try again.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text("Couldn't load deals"), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    expect(retries, 1);
  });

  testWidgets('AppFormSection and AppIconContainer keep content focused', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppFormSection(
            title: 'Product',
            description: 'Tell members what the group is buying.',
            icon: Icons.inventory_2_outlined,
            children: [Text('Product name field')],
          ),
        ),
      ),
    );

    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Tell members what the group is buying.'), findsOneWidget);
    expect(find.byType(AppIconContainer), findsOneWidget);
    expect(find.text('Product name field'), findsOneWidget);
  });
}
