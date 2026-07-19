import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/receipt_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ReceiptParser();

  group('ReceiptParser', () {
    test('reads product, total, and quantity from a simple receipt', () {
      final result = parser.parse(
        'SUPER SAVER MART\n'
        'Rice Sack 25kg      900.00\n'
        'TOTAL              900.00\n'
        'CASH             1000.00\n'
        'CHANGE            100.00',
      );

      expect(result.productName, 'Rice Sack');
      expect(result.totalPrice, 900.0);
      expect(result.amount, 25.0);
      expect(result.unit, DealUnit.kg);
      expect(result.isEmpty, isFalse);
    });

    test('prefers a labelled total over a larger unrelated number', () {
      // The CASH tendered (1000) is larger than the total (900), but the total
      // line is what the receipt itself calls the total.
      final result = parser.parse(
        'Cooking Oil 6L   540.00\n'
        'TOTAL            540.00\n'
        'CASH            1000.00',
      );

      expect(result.totalPrice, 540.0);
    });

    test('ignores cash tendered when falling back to the largest amount', () {
      // No label ties a number to "total" on its own line, and the cash (1000)
      // is larger than the price (900) — the tender must not win.
      final result = parser.parse(
        'Rice Sack 25kg 900.00\n'
        'CASH 1000.00\n'
        'CHANGE 100.00',
      );
      expect(result.totalPrice, 900.0);
    });

    test('reads a total whose amount is on the next line', () {
      // OCR can drop the amount onto the line below its label.
      final result = parser.parse(
        'TOTAL\n'
        '900.00\n'
        'CASH\n'
        '1000.00',
      );
      expect(result.totalPrice, 900.0);
    });

    test('handles thousands separators', () {
      final result = parser.parse('TOTAL   1,250.50');
      expect(result.totalPrice, 1250.5);
    });

    test('falls back to the largest amount when no total is labelled', () {
      final result = parser.parse(
        'Detergent 6L   360.00\n'
        'Eggs 30pcs     255.00',
      );
      expect(result.totalPrice, 360.0);
    });

    test('maps unit words to DealUnit and ignores unsupported units', () {
      expect(parser.parse('Water 24 bottles 380').unit, DealUnit.bottles);
      expect(parser.parse('Coffee 60 sachets 900').unit, DealUnit.sachets);
      expect(parser.parse('Eggs 30 pcs 255').unit, DealUnit.pieces);
      // Grams are not a DealUnit, so no quantity is claimed from them.
      expect(parser.parse('Sugar 500g 45').unit, isNull);
      expect(parser.parse('Sugar 500g 45').amount, isNull);
    });

    test('strips the price and quantity out of the product name', () {
      final result = parser.parse('Laundry Detergent 6L 360.00');
      expect(result.productName, 'Laundry Detergent');
    });

    test('skips receipt furniture when choosing the product name', () {
      final result = parser.parse(
        'OFFICIAL RECEIPT\n'
        'Thank you for shopping\n'
        'Bottled Water 24pk 380.00\n'
        'VAT 12%   40.71\n'
        'TOTAL 380.00',
      );
      expect(result.productName, 'Bottled Water');
    });

    test('empty or textless input yields an empty extraction', () {
      final result = parser.parse('');
      expect(result.isEmpty, isTrue);
      expect(result.productName, isNull);
      expect(result.totalPrice, isNull);
      expect(result.amount, isNull);
    });

    test('a barcode-only scan is still a useful extraction', () {
      const result = ReceiptExtraction(barcodeValue: '4801234567890');

      expect(result.isEmpty, isFalse);
      expect(result.barcodeValue, '4801234567890');
    });

    test('does not treat long barcode digits as the receipt total', () {
      final result = parser.parse(
        '4801234567890\n'
        'Rice Sack 25kg 900.00',
      );

      expect(result.totalPrice, 900.0);
    });

    test('parses a column-separated receipt reassembled by position', () {
      // Reproduces what ML Kit returned for a real receipt: every label first,
      // then every amount, in separate blocks. Laid out by position, the labels
      // and amounts sit on the same rows, so the total (900) must win over the
      // cash tendered (1000).
      ReceiptTextLine at(String text, double y, double left) =>
          ReceiptTextLine(text: text, top: y - 16, bottom: y + 16, left: left);
      final lines = <ReceiptTextLine>[
        // Labels column, top to bottom.
        at('SUPER SAVER MART', 40, 150),
        at('Rice Sack 25 kg', 160, 40),
        at('SUBTOTAL', 240, 40),
        at('VAT 12%', 290, 40),
        at('TOTAL', 340, 40),
        at('CASH', 390, 40),
        at('CHANGE', 440, 40),
        // Amounts column, returned separately by OCR.
        at('900.00', 160, 430),
        at('900.00', 240, 430),
        at('96.43', 290, 460),
        at('900.00', 340, 430),
        at('1000.00', 390, 410),
        at('100.00', 440, 430),
      ];

      final result = parser.parse(assembleReceiptText(lines));
      expect(result.totalPrice, 900.0);
      expect(result.productName, 'Rice Sack');
      expect(result.amount, 25.0);
      expect(result.unit, DealUnit.kg);
    });

    test('assembleReceiptText returns empty for no lines', () {
      expect(assembleReceiptText(const []), '');
    });

    test('is deterministic and keeps the raw text', () {
      const text = 'Rice 25kg 900.00\nTOTAL 900.00';
      final first = parser.parse(text);
      final second = parser.parse(text);
      expect(first.productName, second.productName);
      expect(first.totalPrice, second.totalPrice);
      expect(first.rawText, text);
    });
  });
}
