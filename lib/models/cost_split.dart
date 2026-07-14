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
