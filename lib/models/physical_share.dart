import 'deal_unit.dart';

/// The slot counts a deal may be posted with. Mirrors kMinDealSlots /
/// kMaxDealSlots in create_deal_viewmodel.dart; these bound the counts we are
/// willing to *suggest* when the goods will not divide.
const int _minSuggestedSlots = 2;
const int _maxSuggestedSlots = 50;

/// What one student physically receives from a bulk buy.
///
/// The goods twin of [CostSplit]. Money and goods behave differently, and the
/// difference is the whole point of this type: an odd centavo can be rounded up
/// and absorbed by the host, but nobody can collect half an egg. So where the
/// money always reconciles, the goods sometimes simply cannot be divided, and
/// the deal must not exist in that shape.
class PhysicalShare {
  PhysicalShare._({
    required this.amount,
    required this.unit,
    required this.slots,
  });

  factory PhysicalShare.from({
    required double amount,
    required DealUnit unit,
    required int slots,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'A bulk buy needs an amount above zero.',
      );
    }
    if (slots < 1) {
      throw ArgumentError.value(
        slots,
        'slots',
        'A split needs at least one slot.',
      );
    }
    return PhysicalShare._(amount: amount, unit: unit, slots: slots);
  }

  final double amount;
  final DealUnit unit;
  final int slots;

  double get amountPerShare => amount / slots;

  /// Weights and volumes always divide. Countable goods only divide when the
  /// slot count is a factor of the amount.
  bool get dividesEvenly {
    if (unit.continuous) return true;
    if (amount != amount.roundToDouble()) return false;
    return amount.round() % slots == 0;
  }

  /// Whether this amount can be split at *any* allowed slot count. False for a
  /// single item, and for a prime amount larger than the slot ceiling — there is
  /// no honest suggestion to make in either case.
  bool get canBeSplit => unit.continuous || workableSlotCounts.isNotEmpty;

  /// The slot counts that divide these goods evenly. Empty for continuous
  /// goods, which need no suggestion because every count works.
  List<int> get workableSlotCounts {
    if (unit.continuous) return const [];
    if (amount != amount.roundToDouble()) return const [];

    final whole = amount.round();
    return [
      for (var count = _minSuggestedSlots; count <= _maxSuggestedSlots; count++)
        if (whole % count == 0) count,
    ];
  }

  /// "3.57 kg", "6 bottles", "1 bottle".
  String get shareLabel => _label(amountPerShare);

  /// "25 kg", "24 bottles".
  String get totalLabel => _label(amount);

  String _label(double value) {
    final isWhole = value == value.roundToDouble();
    final text = isWhole ? value.round().toString() : value.toStringAsFixed(2);
    final unitLabel = isWhole && value.round() == 1
        ? unit.singularLabel
        : unit.label;
    return '$text $unitLabel';
  }
}
