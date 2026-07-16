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
    DealRepository repository,
  ) async {
    await tester.pumpWidget(
      Provider<DealRepository>.value(
        value: repository,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(CreateDealScreen.route('colon', 'Colon Street Hub')),
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
      final chip = find.byKey(Key('deal-unit-${unit.name}'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
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

    await fillForm(tester);
    expect(find.byKey(const Key('deal-review')), findsOneWidget);
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
