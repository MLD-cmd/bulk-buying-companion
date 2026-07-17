import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/create_deal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    DealRepository repository, {
    ValueChanged<Future<Deal?>>? onRoutePushed,
  }) async {
    await tester.pumpWidget(
      Provider<DealRepository>.value(
        value: repository,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    final result = Navigator.of(
                      context,
                    ).push(CreateDealScreen.route('colon', 'Colon Street Hub'));
                    onRoutePushed?.call(result);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(
    WidgetTester tester, {
    String title = 'Cooking Oil 5L',
    String totalPrice = '750',
    String amount = '1',
    DealUnit? unit,
    String totalSlots = '5',
    String pickupLocation = 'USJR Main Gate',
  }) async {
    await tester.enterText(find.byKey(const Key('deal-title-field')), title);
    await tester.enterText(
      find.byKey(const Key('deal-total-price-field')),
      totalPrice,
    );
    await tester.enterText(find.byKey(const Key('deal-amount-field')), amount);
    if (unit != null) {
      final field = find.byKey(const Key('deal-unit-field'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_unitDisplayName(unit)).last);
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const Key('deal-total-slots-field')),
      totalSlots,
    );
    await tester.enterText(
      find.byKey(const Key('deal-pickup-location-field')),
      pickupLocation,
    );
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.byKey(const Key('deal-submit-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('form groups the existing draft into clear sections', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());

    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.byKey(const Key('deal-title-field')), findsOneWidget);
    expect(find.byKey(const Key('deal-total-price-field')), findsOneWidget);
    expect(find.byKey(const Key('deal-pickup-location-field')), findsOneWidget);
    expect(
      find.byKey(const Key('deal-product-repaint-boundary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('deal-split-repaint-boundary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('deal-pickup-repaint-boundary')),
      findsOneWidget,
    );

    await fillForm(tester);
    expect(find.byKey(const Key('deal-review')), findsOneWidget);
    expect(
      find.byKey(const Key('deal-review-repaint-boundary')),
      findsOneWidget,
    );
  });

  testWidgets('untouched Back leaves without a discard confirmation', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Post a deal'), findsNothing);
    expect(find.text('Discard these details?'), findsNothing);
  });

  testWidgets('Keep editing preserves every entered deal detail', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());
    await fillForm(tester, unit: DealUnit.litre);
    await tester.enterText(
      find.byKey(const Key('deal-description-field')),
      'Five sealed one-litre bottles',
    );
    final category = find.byKey(const Key('deal-category-drinks'));
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard these details?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(
      _textField(tester, const Key('deal-title-field')).controller?.text,
      'Cooking Oil 5L',
    );
    expect(
      _textField(tester, const Key('deal-description-field')).controller?.text,
      'Five sealed one-litre bottles',
    );
    expect(
      _textField(tester, const Key('deal-total-price-field')).controller?.text,
      '750',
    );
    expect(
      _textField(tester, const Key('deal-amount-field')).controller?.text,
      '1',
    );
    expect(
      _textField(tester, const Key('deal-total-slots-field')).controller?.text,
      '5',
    );
    expect(
      _textField(
        tester,
        const Key('deal-pickup-location-field'),
      ).controller?.text,
      'USJR Main Gate',
    );
    expect(find.text('Litres (L)'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('deal-category-drinks')))
          .selected,
      isTrue,
    );
  });

  testWidgets('Discard leaves the form exactly once', (tester) async {
    final observer = _DealRouteObserver();
    await tester.pumpWidget(
      Provider<DealRepository>.value(
        value: MockDealRepository(),
        child: MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(CreateDealScreen.route('colon', 'Colon Street Hub')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deal-title-field')),
      'Rice Sack',
    );
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Post a deal'), findsNothing);
    expect(observer.dealRoutePops, 1);
  });

  testWidgets('rapid Back requests do not stack discard dialogs', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());
    await tester.enterText(
      find.byKey(const Key('deal-title-field')),
      'Rice Sack',
    );

    final guard = tester.widget<PopScope<Deal>>(find.byType(PopScope<Deal>));
    guard.onPopInvokedWithResult?.call(false, null);
    guard.onPopInvokedWithResult?.call(false, null);
    await tester.pumpAndSettle();

    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('disposing an open discard dialog has no stale callback', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());
    await tester.enterText(
      find.byKey(const Key('deal-title-field')),
      'Rice Sack',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Back cannot discard or dispose a publish in progress', (
    tester,
  ) async {
    final repository = _DelayedDealRepository();
    await pumpScreen(tester, repository);
    await fillForm(tester);

    final submitButton = find.byKey(const Key('deal-submit-button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(repository.createCalls, 1);
    expect(find.text('Publishing…'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Post a deal'), findsOneWidget);
    expect(find.text('Discard these details?'), findsNothing);

    await tester.pageBack();
    await tester.pump();
    expect(find.text('Post a deal'), findsOneWidget);
    expect(find.text('Discard these details?'), findsNothing);

    final guard = tester.widget<PopScope<Deal>>(find.byType(PopScope<Deal>));
    guard.onPopInvokedWithResult?.call(false, null);
    await tester.pump();
    expect(find.text('Discard these details?'), findsNothing);

    repository.fail(
      const DealFailure('Could not publish this deal right now.'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not publish this deal right now.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets(
    'pending publish blocks Help and returns its Deal from the route',
    (tester) async {
      final repository = _DelayedDealRepository();
      late Future<Deal?> routeResult;
      await pumpScreen(
        tester,
        repository,
        onRoutePushed: (result) => routeResult = result,
      );
      await fillForm(tester);

      final help = find.widgetWithIcon(IconButton, Icons.help_outline);
      final submitButton = find.byKey(const Key('deal-submit-button'));
      final staleHelp = tester.widget<IconButton>(help).onPressed!;
      final stalePublish = tester.widget<FilledButton>(submitButton).onPressed!;
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();

      expect(tester.widget<IconButton>(help).onPressed, isNull);
      expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);
      expect(
        tester
            .getSemantics(find.byKey(const Key('deal-help-button-semantics')))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      expect(
        tester.getSemantics(submitButton).flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      expect(tester.getSemantics(submitButton).label, contains('Publishing'));

      staleHelp();
      stalePublish();
      await tester.pump();

      expect(repository.createCalls, 1);
      expect(find.text('How to post a deal'), findsNothing);

      final published = _publishedDeal();
      repository.succeed(published);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(await routeResult, same(published));
      expect(find.text('Post a deal'), findsNothing);
      expect(find.text('How to post a deal'), findsNothing);

      staleHelp();
      stalePublish();
      await tester.pump();
      expect(repository.createCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending publish blocks current and stale deadline clearing', (
    tester,
  ) async {
    final repository = _DelayedDealRepository();
    await pumpScreen(tester, repository);
    await fillForm(tester);

    final deadlineButton = find.byKey(const Key('deal-deadline-button'));
    await tester.ensureVisible(deadlineButton);
    await tester.tap(deadlineButton);
    await tester.pumpAndSettle();

    final deadline = DateTime.now().add(const Duration(days: 4));
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    picker.onDateChanged(deadline);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final deadlineLabel =
        'Closes ${deadline.month}/${deadline.day}/${deadline.year}';
    final clearButton = find.widgetWithIcon(IconButton, Icons.close);
    final staleClear = tester.widget<IconButton>(clearButton).onPressed!;
    expect(find.text(deadlineLabel), findsWidgets);

    final submitButton = find.byKey(const Key('deal-submit-button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(tester.widget<IconButton>(clearButton).onPressed, isNull);
    staleClear();
    await tester.pump();

    expect(find.text(deadlineLabel), findsWidgets);
    expect(find.byTooltip('Clear deadline'), findsOneWidget);
    expect(repository.createCalls, 1);

    repository.succeed(_publishedDeal());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing edited text still protects the draft', (tester) async {
    await pumpScreen(tester, MockDealRepository());
    final title = find.byKey(const Key('deal-title-field'));
    await tester.enterText(title, 'Rice Sack');
    await tester.enterText(title, '');

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('category and unit changes protect the draft', (tester) async {
    await pumpScreen(tester, MockDealRepository());
    final category = find.byKey(const Key('deal-category-drinks'));
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    final unit = find.byKey(const Key('deal-unit-field'));
    await tester.ensureVisible(unit);
    await tester.tap(unit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pieces').last);
    await tester.pumpAndSettle();
    expect(find.text('Pieces'), findsOneWidget);
  });

  testWidgets('unit dropdown retains all measurements with clear names', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());

    final field = find.byKey(const Key('deal-unit-field'));
    expect(field, findsOneWidget);
    expect(find.byType(DropdownButtonFormField<DealUnit>), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(DealCategory.values.length));

    final dropdown = tester.widget<DropdownButton<DealUnit>>(
      find.descendant(
        of: field,
        matching: find.byType(DropdownButton<DealUnit>),
      ),
    );
    final labels = dropdown.items!
        .map((item) => (item.child as Text).data)
        .toList();
    expect(labels, <String>[
      'Kilograms (kg)',
      'Litres (L)',
      'Pieces',
      'Packs',
      'Bottles',
      'Cans',
      'Sachets',
    ]);

    for (final unit in DealUnit.values) {
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_unitDisplayName(unit)).last);
      await tester.pumpAndSettle();
      expect(find.text(_unitDisplayName(unit)), findsOneWidget);
    }

    final semantics = tester.getSemantics(field);
    expect('${semantics.label} ${semantics.value}', contains('Sachets'));
  });

  testWidgets('setting and clearing a deadline keeps the draft protected', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());
    final deadline = find.byKey(const Key('deal-deadline-button'));
    await tester.ensureVisible(deadline);
    await tester.tap(deadline);
    await tester.pumpAndSettle();

    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    picker.onDateChanged(DateTime.now().add(const Duration(days: 4)));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Closes '), findsWidgets);
    await tester.tap(find.byTooltip('Clear deadline'));
    await tester.pump();
    expect(find.text('Set a deadline (optional)'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('keyboard actions progress through deal fields', (tester) async {
    await pumpScreen(tester, MockDealRepository());

    final fields = <Key>[
      const Key('deal-title-field'),
      const Key('deal-description-field'),
      const Key('deal-total-price-field'),
      const Key('deal-amount-field'),
      const Key('deal-total-slots-field'),
      const Key('deal-pickup-location-field'),
    ];
    final actions = <TextInputAction>[
      TextInputAction.next,
      TextInputAction.next,
      TextInputAction.next,
      TextInputAction.next,
      TextInputAction.next,
      TextInputAction.done,
    ];

    for (var index = 0; index < fields.length; index++) {
      final field = _textField(tester, fields[index]);
      expect(field.textInputAction, actions[index]);
    }

    await tester.tap(find.byKey(fields.first));
    await tester.pump();
    for (var index = 1; index < fields.length; index++) {
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      final field = _textField(tester, fields[index]);
      expect(field.focusNode?.hasFocus, isTrue);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(_textField(tester, fields.last).focusNode?.hasFocus, isFalse);
  });

  testWidgets('invalid submit focuses the first invalid field', (tester) async {
    await pumpScreen(tester, MockDealRepository());

    await submit(tester);

    final title = _textField(tester, const Key('deal-title-field'));
    expect(title.focusNode?.hasFocus, isTrue);
  });

  testWidgets('validation focus follows the visual field order', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());
    await tester.enterText(
      find.byKey(const Key('deal-title-field')),
      'Rice Sack',
    );
    await tester.enterText(
      find.byKey(const Key('deal-description-field')),
      'x' * 281,
    );

    await submit(tester);

    expect(
      _textField(
        tester,
        const Key('deal-description-field'),
      ).focusNode?.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byKey(const Key('deal-description-field')), '');
    await submit(tester);

    expect(
      _textField(
        tester,
        const Key('deal-total-price-field'),
      ).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('Post Deal help explains only the existing publish flow', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());

    final help = find.widgetWithIcon(IconButton, Icons.help_outline);
    final helpSemantics = find.byKey(const Key('deal-help-button-semantics'));
    expect(help, findsOneWidget);
    expect(helpSemantics, findsOneWidget);
    expect(tester.getSize(help).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(helpSemantics).label, 'How to post a deal');
    expect(tester.getSemantics(helpSemantics).flagsCollection.isButton, isTrue);

    await tester.tap(help);
    await tester.pumpAndSettle();

    expect(find.text('How to post a deal'), findsOneWidget);
    expect(find.text('Product'), findsWidgets);
    expect(find.text('Split'), findsWidgets);
    expect(find.text('Pickup and deadline'), findsOneWidget);
    // The sheet scrolls, so the later steps are offstage rather than absent.
    expect(find.text('Payment', skipOffstage: false), findsWidgets);
    expect(find.text('Review', skipOffstage: false), findsWidgets);
    expect(find.text('Publish', skipOffstage: false), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('student publishes a deal and it lands on the hub feed', (
    tester,
  ) async {
    final repository = MockDealRepository();
    await pumpScreen(tester, repository);

    await fillForm(tester);
    final chip = find.byKey(const Key('deal-category-pantry'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(
      tester.widget<ChoiceChip>(chip).selected,
      isTrue,
      reason: 'tapping the chip should select the category',
    );

    await submit(tester);

    // Popped back to the launching screen.
    expect(find.text('Post a deal'), findsNothing);
    expect(find.text('Discard these details?'), findsNothing);

    final deals = await repository.getDeals('colon');
    final published = deals.firstWhere(
      (deal) => deal.title == 'Cooking Oil 5L',
    );
    expect(published.category, DealCategory.pantry);
    expect(published.totalPrice, 750);
    expect(published.totalSlots, 5);
    // The host holds one of the slots they post.
    expect(published.availableSlots, 4);
    expect(published.status, DealStatus.open);
  });

  testWidgets('student can add manual payment instructions to the deal', (
    tester,
  ) async {
    final repository = _CapturingDealRepository();
    await pumpScreen(tester, repository);

    await fillForm(tester);
    await tester.enterText(
      find.byKey(const Key('deal-payment-method-field')),
      'GCash',
    );
    await tester.enterText(
      find.byKey(const Key('deal-payment-account-name-field')),
      'Marco Villanueva',
    );
    await tester.enterText(
      find.byKey(const Key('deal-payment-account-handle-field')),
      '09171234567',
    );
    await tester.enterText(
      find.byKey(const Key('deal-payment-instructions-field')),
      'Send a screenshot after paying.',
    );

    await submit(tester);

    expect(repository.createdDraft, isNotNull);
    expect(repository.createdDraft!.paymentMethod, 'GCash');
    expect(repository.createdDraft!.paymentAccountName, 'Marco Villanueva');
    expect(repository.createdDraft!.paymentAccountHandle, '09171234567');
    expect(
      repository.createdDraft!.paymentInstructions,
      'Send a screenshot after paying.',
    );
  });

  testWidgets('shows the per-share price before publishing', (tester) async {
    await pumpScreen(tester, MockDealRepository());

    expect(find.byKey(const Key('deal-split-preview')), findsNothing);

    await fillForm(tester, totalPrice: '900', totalSlots: '5');

    expect(find.text('Each student pays P180'), findsOneWidget);
  });

  testWidgets('states the surplus when the split does not divide evenly', (
    tester,
  ) async {
    await pumpScreen(tester, MockDealRepository());

    await fillForm(tester, totalPrice: '900', totalSlots: '7');

    expect(find.text('Each student pays P128.58'), findsOneWidget);
    expect(find.byKey(const Key('deal-split-surplus')), findsOneWidget);
  });

  testWidgets('says nothing about a surplus on an even split', (tester) async {
    await pumpScreen(tester, MockDealRepository());

    await fillForm(tester, totalPrice: '900', totalSlots: '5');

    expect(find.text('Each student pays P180'), findsOneWidget);
    expect(find.byKey(const Key('deal-split-surplus')), findsNothing);
  });

  testWidgets('refuses to publish an incomplete deal', (tester) async {
    final repository = _RecordingDealRepository();
    await pumpScreen(tester, repository);

    await submit(tester);

    expect(find.text('Enter the product name.'), findsOneWidget);
    expect(find.text('Enter the total price.'), findsOneWidget);
    expect(find.text('Enter where the pickup happens.'), findsOneWidget);
    expect(repository.createCalls, 0);
    // Still on the form, not popped.
    expect(find.text('Post a deal'), findsOneWidget);
  });

  testWidgets('refuses a one-slot split', (tester) async {
    final repository = _RecordingDealRepository();
    await pumpScreen(tester, repository);

    await fillForm(tester, totalSlots: '1');
    await submit(tester);

    expect(find.text('Slots must be at least 2.'), findsOneWidget);
    expect(repository.createCalls, 0);
  });

  testWidgets('displays a backend failure without leaving the form', (
    tester,
  ) async {
    await pumpScreen(tester, _RefusingDealRepository());

    await fillForm(tester);
    await submit(tester);

    expect(
      find.text('You do not have permission to post a deal in this hub.'),
      findsOneWidget,
    );
    expect(find.text('Post a deal'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these details?'), findsOneWidget);
  });

  testWidgets('shows what each student physically gets', (tester) async {
    await pumpScreen(tester, MockDealRepository());

    await fillForm(tester, totalPrice: '900', amount: '25', totalSlots: '7');

    expect(find.text('Each student pays P128.58'), findsOneWidget);
    expect(find.byKey(const Key('deal-share-preview')), findsOneWidget);
    expect(find.text('Each student gets 3.57 kg'), findsOneWidget);
  });

  testWidgets('refuses goods that will not divide, and names what will', (
    tester,
  ) async {
    final repository = _RecordingDealRepository();
    await pumpScreen(tester, repository);

    await fillForm(
      tester,
      totalPrice: '255',
      amount: '30',
      unit: DealUnit.pieces,
      totalSlots: '4',
    );
    await submit(tester);

    expect(
      find.text('30 pieces across 4 slots leaves 7.5 each. Try 3 or 5 slots.'),
      findsOneWidget,
    );
  });

  testWidgets('the refusal clears as soon as the slot count is corrected', (
    tester,
  ) async {
    await pumpScreen(tester, _RecordingDealRepository());

    await fillForm(
      tester,
      totalPrice: '240',
      amount: '30',
      unit: DealUnit.pieces,
      totalSlots: '4',
    );
    await submit(tester);

    await tester.enterText(
      find.byKey(const Key('deal-total-slots-field')),
      '5',
    );
    await tester.pump();

    // Otherwise the stale refusal sits directly above a preview that already
    // says the goods divide, and the poster is told both at once.
    expect(
      find.text('30 pieces across 4 slots leaves 7.5 each. Try 3 or 5 slots.'),
      findsNothing,
    );
    expect(find.text('Each student gets 6 pieces'), findsOneWidget);
  });
}

String _unitDisplayName(DealUnit unit) => switch (unit) {
  DealUnit.kg => 'Kilograms (kg)',
  DealUnit.litre => 'Litres (L)',
  DealUnit.pieces => 'Pieces',
  DealUnit.packs => 'Packs',
  DealUnit.bottles => 'Bottles',
  DealUnit.cans => 'Cans',
  DealUnit.sachets => 'Sachets',
};

TextField _textField(WidgetTester tester, Key key) {
  return tester.widget<TextField>(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
  );
}

class _DealRouteObserver extends NavigatorObserver {
  int dealRoutePops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute<Deal>) dealRoutePops++;
    super.didPop(route, previousRoute);
  }
}

class _RecordingDealRepository implements DealRepository {
  int createCalls = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }

  @override
  Future<Deal> createDeal(DealDraft draft) async {
    createCalls++;
    throw UnimplementedError();
  }
}

class _CapturingDealRepository implements DealRepository {
  DealDraft? createdDraft;

  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }

  @override
  Future<Deal> createDeal(DealDraft draft) async {
    createdDraft = draft;
    return Deal(
      id: 'captured',
      hubId: draft.hubId,
      title: draft.title,
      description: draft.description,
      category: draft.category,
      totalPrice: draft.totalPrice,
      amount: draft.amount,
      unit: draft.unit,
      availableSlots: draft.totalSlots - 1,
      totalSlots: draft.totalSlots,
      pickupLocation: draft.pickupLocation,
      paymentMethod: draft.paymentMethod,
      paymentAccountName: draft.paymentAccountName,
      paymentAccountHandle: draft.paymentAccountHandle,
      paymentInstructions: draft.paymentInstructions,
      paidCount: 1,
    );
  }
}

class _RefusingDealRepository implements DealRepository {
  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw const DealFailure(
      'You do not have permission to post a deal in this hub.',
    );
  }
}

class _DelayedDealRepository implements DealRepository {
  final Completer<Deal> _completion = Completer<Deal>();
  int createCalls = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Future<Deal> createDeal(DealDraft draft) {
    createCalls++;
    return _completion.future;
  }

  void succeed(Deal deal) => _completion.complete(deal);

  void fail(Object error) => _completion.completeError(error);

  /// The default on [DealRepository]; `implements` does not inherit it.
  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }
}

Deal _publishedDeal() => const Deal(
  id: 'published-deal',
  hubId: 'colon',
  title: 'Cooking Oil 5L',
  category: DealCategory.grocery,
  totalPrice: 750,
  amount: 1,
  unit: DealUnit.litre,
  availableSlots: 4,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);
