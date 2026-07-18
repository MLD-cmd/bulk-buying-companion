import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/services/receipt_scanner.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/receipt_extraction.dart';
import 'package:bulk_buying_companion/ui/split_board/create_deal_screen.dart';
import 'package:bulk_buying_companion/ui/split_board/create_deal_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeDealRepository implements DealRepository {
  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield const [];
  }

  @override
  Future<Deal> createDeal(DealDraft draft) => throw UnimplementedError();
}

void main() {
  group('CreateDealViewModel.scanReceipt', () {
    test('returns the extraction and toggles the scanning flag', () async {
      final viewModel = CreateDealViewModel(
        dealRepository: _FakeDealRepository(),
        receiptScanner: MockReceiptScanner(
          result: const ReceiptExtraction(
            productName: 'Rice Sack',
            totalPrice: 900,
            amount: 25,
            unit: DealUnit.kg,
          ),
        ),
      );

      expect(viewModel.scanningEnabled, isTrue);
      final future = viewModel.scanReceipt(ReceiptImageSource.camera);
      expect(viewModel.isScanning, isTrue);

      final extraction = await future;
      expect(viewModel.isScanning, isFalse);
      expect(extraction?.productName, 'Rice Sack');
      expect(viewModel.scanErrorMessage, isNull);
    });

    test('a cancelled pick returns null without an error', () async {
      final viewModel = CreateDealViewModel(
        dealRepository: _FakeDealRepository(),
        receiptScanner: MockReceiptScanner(cancels: true),
      );

      expect(await viewModel.scanReceipt(ReceiptImageSource.gallery), isNull);
      expect(viewModel.scanErrorMessage, isNull);
    });

    test('a scan failure surfaces its message', () async {
      final viewModel = CreateDealViewModel(
        dealRepository: _FakeDealRepository(),
        receiptScanner: MockReceiptScanner(
          failure: const ReceiptScanFailure('Could not read that photo.'),
        ),
      );

      expect(await viewModel.scanReceipt(ReceiptImageSource.camera), isNull);
      expect(viewModel.scanErrorMessage, 'Could not read that photo.');
    });

    test('scanning is disabled when no scanner is wired in', () async {
      final viewModel = CreateDealViewModel(
        dealRepository: _FakeDealRepository(),
      );
      expect(viewModel.scanningEnabled, isFalse);
      expect(await viewModel.scanReceipt(ReceiptImageSource.camera), isNull);
    });
  });

  testWidgets('scanning a receipt fills the form fields', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DealRepository>.value(value: _FakeDealRepository()),
          Provider<ReceiptScanner>.value(
            value: MockReceiptScanner(
              result: const ReceiptExtraction(
                productName: 'Bottled Water',
                totalPrice: 380,
                amount: 24,
                unit: DealUnit.bottles,
              ),
            ),
          ),
        ],
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

    // The scan affordance is present because a scanner was provided.
    expect(find.byKey(const Key('deal-scan-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('deal-scan-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-source-camera')));
    await tester.pumpAndSettle();

    final title = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('deal-title-field')),
        matching: find.byType(TextField),
      ),
    );
    final price = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('deal-total-price-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(title.controller?.text, 'Bottled Water');
    expect(price.controller?.text, '380');
    expect(
      find.text('Scanned — check the details before publishing.'),
      findsOneWidget,
    );
  });
}
