import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulk_buying_companion/main.dart';

void main() {
  testWidgets('Join Hub screen loads and lists hubs', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await tester.pumpAndSettle();

    expect(find.text('Find your hub'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsOneWidget);
  });

  testWidgets('Search filters the hub list', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'colon');
    await tester.pump();

    expect(find.text('Colon Street Hub'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsNothing);
  });

  testWidgets('Joining a hub shows the current-hub banner', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join').first);
    await tester.pumpAndSettle();

    expect(find.text('CURRENT HUB'), findsOneWidget);
    expect(find.text('Joined'), findsOneWidget);
  });

  testWidgets('Profile screen shows the joined hub after joining', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsOneWidget);
    expect(find.textContaining("haven't joined"), findsNothing);
  });

  testWidgets('Profile screen shows empty state before joining', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining("haven't joined"), findsOneWidget);
  });
}
