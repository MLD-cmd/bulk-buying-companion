import 'dart:math' as math;

import 'deal_unit.dart';

/// One line of recognised text with where it sits on the page. OCR reads a
/// two-column receipt column by column — every label, then every amount — so
/// the raw text order divorces "TOTAL" from its price. The vertical position is
/// what puts them back together.
class ReceiptTextLine {
  const ReceiptTextLine({
    required this.text,
    required this.top,
    required this.bottom,
    required this.left,
  });

  final String text;
  final double top;
  final double bottom;
  final double left;

  double get centerY => (top + bottom) / 2;
  double get height => (bottom - top).abs();
}

/// Rebuilds the receipt's visual rows from positioned lines: lines that sit at
/// the same height are one row, read left to right. This undoes OCR's
/// column-by-column reading order, so a label and the amount printed beside it
/// land on the same text line — which is all [ReceiptParser] needs to pair
/// them.
///
/// Pure and geometry-only, so a test can feed it hand-placed boxes and pin the
/// row grouping down without a camera or ML Kit.
String assembleReceiptText(List<ReceiptTextLine> lines) {
  if (lines.isEmpty) return '';

  final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<ReceiptTextLine>>[];

  for (final line in sorted) {
    if (rows.isEmpty) {
      rows.add([line]);
      continue;
    }
    final row = rows.last;
    final rowTop = row.map((l) => l.top).reduce(math.min);
    final rowBottom = row.map((l) => l.bottom).reduce(math.max);
    // A line joins the current row when its centre falls within that row's
    // vertical band, give or take half a line's height for print that is not
    // perfectly level.
    final tolerance = line.height * 0.5;
    if (line.centerY >= rowTop - tolerance &&
        line.centerY <= rowBottom + tolerance) {
      row.add(line);
    } else {
      rows.add([line]);
    }
  }

  return rows
      .map(
        (row) => ([...row]..sort((a, b) => a.left.compareTo(b.left)))
            .map((l) => l.text)
            .join('  '),
      )
      .join('\n');
}

/// What a receipt scan managed to pull out of the printed text. Every field is
/// nullable and every one is a guess: OCR on a phone photo of a crumpled
/// receipt is never certain, so nothing here is trusted enough to publish on
/// its own. The Create Deal form is pre-filled with whatever was found and the
/// student corrects it — this is the input to that step, not a finished deal.
class ReceiptExtraction {
  const ReceiptExtraction({
    this.productName,
    this.totalPrice,
    this.amount,
    this.unit,
    this.rawText = '',
  });

  /// The item being bought, with the price and quantity stripped back off the
  /// line they were read from.
  final String? productName;

  /// The peso figure to split. The receipt's own total when it prints one,
  /// otherwise the largest amount on it.
  final double? totalPrice;

  /// How much the buy covers, paired with [unit]. Null unless a quantity and a
  /// unit the app understands were found together.
  final double? amount;
  final DealUnit? unit;

  /// The full recognised text, kept so the parser's guesses can be checked
  /// against what was actually read.
  final String rawText;

  /// True when nothing usable was found — the form has nothing to pre-fill, so
  /// the caller can tell the student the scan came up empty rather than
  /// silently doing nothing.
  bool get isEmpty =>
      productName == null && totalPrice == null && amount == null;
}

/// Turns raw OCR text into a [ReceiptExtraction]. Pure and synchronous: it is
/// handed a string and returns a guess, reading nothing and storing nothing, so
/// the same text always parses the same way and every rule can be pinned down
/// by a test.
///
/// The rules are deliberately simple and forgiving. They will get some receipts
/// wrong — that is what the student's review step is for — so the parser aims
/// to be right often and never to throw, rather than to be clever.
class ReceiptParser {
  const ReceiptParser();

  /// A peso amount: optional currency mark, then digits with optional thousands
  /// separators and an optional two-decimal tail. Captures the number itself.
  static final RegExp _money = RegExp(
    r'(?:₱|php|p)?\s*(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// A quantity glued to a unit the app supports: "25kg", "24 bottles",
  /// "6 pcs". Grams and millilitres are left out on purpose, matching
  /// [DealUnit] — the app has no unit to map them to.
  static final RegExp _quantity = RegExp(
    r'(\d+(?:\.\d+)?)\s*'
    r'(kgs?|kilos?|kilograms?|liters?|litres?|l|pcs?|pieces?|'
    r'packs?|pks?|bottles?|btls?|cans?|sachets?)\b',
    caseSensitive: false,
  );

  /// Money handed over, not the price of the goods: on a two-column receipt the
  /// cash tendered often prints larger than the total, so its amount must not
  /// win the "largest amount" fallback.
  static final RegExp _tender = RegExp(
    r'\bcash\b|\bchange\b|\btender\b',
    caseSensitive: false,
  );

  /// Lines that are never the product: receipt furniture, totals, tax, tender.
  static final RegExp _noise = RegExp(
    r'\b(sub)?total\b|\bvat\b|\btax\b|\bcash\b|\bchange\b|\btender\b|'
    r'\bamount\s+due\b|\bbalance\b|\breceipt\b|\binvoice\b|\bofficial\b|'
    r'\bthank\b|\bcashier\b|\btin\b|\bqty\b|\bdate\b|\btime\b',
    caseSensitive: false,
  );

  ReceiptExtraction parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final totalPrice = _findTotalPrice(lines);
    final (amount, unit) = _findQuantity(lines);
    final productName = _findProductName(lines);

    return ReceiptExtraction(
      productName: productName,
      totalPrice: totalPrice,
      amount: amount,
      unit: unit,
      rawText: rawText,
    );
  }

  /// The receipt's own total when a line names one, otherwise the largest
  /// amount printed anywhere. A "total" line wins even when a larger number
  /// appears elsewhere (a barcode, a date), because it is the figure the
  /// receipt itself calls the total.
  double? _findTotalPrice(List<String> lines) {
    double? labelledTotal;
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      // "subtotal" is a weaker signal than "total"; only fall back to it.
      final isTotal = lower.contains('total') && !lower.contains('subtotal');
      if (!isTotal) continue;

      var onLine = _amountsIn(lines[i]);
      // A two-column receipt can split the label and its amount onto separate
      // OCR lines. When the total line carries no number, the amount is most
      // likely the very next line.
      if (onLine.isEmpty && i + 1 < lines.length) {
        onLine = _amountsIn(lines[i + 1]);
      }
      if (onLine.isNotEmpty) {
        labelledTotal = onLine.reduce((a, b) => a > b ? a : b);
      }
    }
    if (labelledTotal != null) return labelledTotal;

    // Fallback: the largest amount, but not one printed on a tender line —
    // the cash handed over is not what the deal costs.
    final all = [
      for (final line in lines)
        if (!_tender.hasMatch(line)) ..._amountsIn(line),
    ];
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a > b ? a : b);
  }

  (double?, DealUnit?) _findQuantity(List<String> lines) {
    for (final line in lines) {
      final match = _quantity.firstMatch(line);
      if (match == null) continue;
      final amount = double.tryParse(match.group(1)!);
      final unit = _unitFromToken(match.group(2)!);
      if (amount != null && amount > 0 && unit != null) return (amount, unit);
    }
    return (null, null);
  }

  /// The most product-like line: a line item (letters next to a price) is the
  /// best bet, otherwise the longest run of letters that is not receipt
  /// furniture. The price and quantity are stripped off so the name does not
  /// carry "900.00" or "25kg" into the form.
  String? _findProductName(List<String> lines) {
    String? best;
    var bestScore = -1;

    for (final line in lines) {
      if (_noise.hasMatch(line)) continue;
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length < 3) continue;

      final cleaned = _stripPriceAndQuantity(line);
      if (cleaned.length < 3) continue;

      // A line that also carries a price is almost certainly an item line, so
      // it outscores a bare word (a store name, an address fragment).
      final hasPrice = _amountsIn(line).isNotEmpty;
      final score = cleaned.length + (hasPrice ? 100 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = cleaned;
      }
    }
    return best;
  }

  String _stripPriceAndQuantity(String line) {
    return line
        .replaceAll(_quantity, ' ')
        .replaceAll(_money, ' ')
        // Leftover currency marks and stray separators.
        .replaceAll(RegExp(r'[₱$*#:]'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  List<double> _amountsIn(String line) {
    return [
      for (final match in _money.allMatches(line))
        if (double.tryParse(match.group(1)!.replaceAll(',', '')) case final v?)
          if (v > 0) v,
    ];
  }

  DealUnit? _unitFromToken(String token) {
    final t = token.toLowerCase();
    if (t.startsWith('kg') || t.startsWith('kilo')) return DealUnit.kg;
    if (t == 'l' || t.startsWith('lit')) return DealUnit.litre;
    if (t.startsWith('pc') || t.startsWith('piece')) return DealUnit.pieces;
    if (t.startsWith('pack') || t.startsWith('pk')) return DealUnit.packs;
    if (t.startsWith('bottle') || t.startsWith('btl')) return DealUnit.bottles;
    if (t.startsWith('can')) return DealUnit.cans;
    if (t.startsWith('sachet')) return DealUnit.sachets;
    return null;
  }
}
