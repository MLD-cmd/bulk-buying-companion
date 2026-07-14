/// The arithmetic of splitting one bulk buy across its slots.
///
/// Done entirely in whole centavos. A floating-point division of pesos cannot
/// promise the shares add back up to the total, and money that does not
/// reconcile is what starts arguments at pickup.
///
/// Shares round *up* to the centavo, so every student pays the same amount and
/// the host is never left covering a shortfall. The few centavos of overshoot
/// are exposed as [surplusCentavos] rather than quietly pocketed.
class CostSplit {
  const CostSplit._({required this.totalCentavos, required this.slots});

  factory CostSplit.from({required double totalPrice, required int slots}) {
    if (slots < 1) {
      throw ArgumentError.value(
        slots,
        'slots',
        'A split needs at least one slot.',
      );
    }
    // `double.tryParse` yields Infinity for '1e400' and NaN for 'NaN', and
    // `.round()` throws on both. Reject them here rather than let an
    // UnsupportedError surface from whatever happens to be doing the
    // arithmetic.
    if (!totalPrice.isFinite) {
      throw ArgumentError.value(
        totalPrice,
        'totalPrice',
        'A split needs a finite total.',
      );
    }
    if (totalPrice > maxTotalPrice) {
      // Past this, (totalPrice * 100).round() saturates at the int64 ceiling
      // and the ceiling division below wraps negative — the shares would stop
      // covering the total, which is the one thing this type promises.
      throw ArgumentError.value(
        totalPrice,
        'totalPrice',
        'A split cannot total more than $maxTotalPrice.',
      );
    }

    final totalCentavos = (totalPrice * 100).round();
    if (totalCentavos < 1) {
      throw ArgumentError.value(
        totalPrice,
        'totalPrice',
        'A split needs a total of at least one centavo.',
      );
    }

    return CostSplit._(totalCentavos: totalCentavos, slots: slots);
  }

  /// For deals that came out of the database, where the row is whatever the
  /// table happens to hold. A malformed deal must not throw from inside a
  /// widget build and take the whole Split Board down with it, so its split is
  /// clamped to the nearest usable one instead. Every legitimate deal is well
  /// inside these bounds and is unaffected.
  factory CostSplit.clamped({required double totalPrice, required int slots}) {
    final price = !totalPrice.isFinite || totalPrice < 0.01
        ? 0.01
        : (totalPrice > maxTotalPrice ? maxTotalPrice : totalPrice);

    return CostSplit.from(totalPrice: price, slots: slots < 1 ? 1 : slots);
  }

  /// No bulk buy on a campus approaches this. It exists to keep the centavo
  /// arithmetic inside int64, so the guarantees below hold for every value the
  /// type will accept.
  static const double maxTotalPrice = 1000000000; // P1 billion

  final int totalCentavos;
  final int slots;

  /// Ceiling division, done on integers so there is no rounding step that can
  /// drift a share off by a centavo.
  int get perShareCentavos => (totalCentavos + slots - 1) ~/ slots;

  int get collectedCentavos => perShareCentavos * slots;

  /// What the host is left holding once every share is in. Never negative:
  /// the shares round up, so they always cover the total.
  int get surplusCentavos => collectedCentavos - totalCentavos;

  bool get isEven => surplusCentavos == 0;

  /// Peso views, for display only — derived from the integers, never used to
  /// compute one.
  double get pricePerShare => perShareCentavos / 100;
  double get collected => collectedCentavos / 100;
  double get surplus => surplusCentavos / 100;
}
