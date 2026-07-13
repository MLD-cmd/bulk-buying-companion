/// A bulk-buying deal posted within a hub.
class Deal {
  const Deal({
    required this.id,
    required this.hubId,
    required this.title,
    required this.category,
    required this.totalPrice,
    required this.quantity,
    required this.availableSlots,
    required this.totalSlots,
    required this.pickupLocation,
    required this.status,
    this.description,
    this.closesAt,
  });

  final String id;
  final String hubId;
  final String title;

  /// Optional detail the poster adds: brand, size, where they are buying it.
  final String? description;
  final DealCategory category;

  /// Cost of the whole bulk buy, before it is split. The per-share price the
  /// student actually pays is derived from this — see [pricePerShare].
  final double totalPrice;

  /// How many units the bulk buy covers (a 24-pack of water is 24).
  final int quantity;

  final int availableSlots;
  final int totalSlots;
  final String pickupLocation;
  final DealStatus status;
  final DateTime? closesAt;

  double get pricePerShare => totalPrice / totalSlots;

  String get priceLabel => '${formatPeso(pricePerShare)}/share';

  String get availableSlotsLabel => '$availableSlots of $totalSlots slots open';

  String get deadlineLabel {
    final deadline = closesAt;
    if (deadline == null) {
      return 'Deadline TBD';
    }
    return 'Closes ${deadline.month}/${deadline.day}/${deadline.year}';
  }
}

/// A deal the student is about to publish, before the backend assigns it an id.
class DealDraft {
  const DealDraft({
    required this.hubId,
    required this.title,
    required this.category,
    required this.totalPrice,
    required this.quantity,
    required this.totalSlots,
    required this.pickupLocation,
    this.description,
    this.closesAt,
  });

  final String hubId;
  final String title;
  final String? description;
  final DealCategory category;
  final double totalPrice;
  final int quantity;
  final int totalSlots;
  final String pickupLocation;
  final DateTime? closesAt;
}

/// Peso amounts, grouped in thousands: 1200.0 -> 'P1,200', 95.5 -> 'P95.50'.
/// Whole amounts drop the decimals, which is how prices are written on campus.
String formatPeso(double amount) {
  final isWhole = amount == amount.roundToDouble();
  final text = isWhole ? amount.round().toString() : amount.toStringAsFixed(2);

  final parts = text.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );

  return parts.length == 1 ? 'P$grouped' : 'P$grouped.${parts[1]}';
}

enum DealCategory {
  grocery('Grocery'),
  household('Household'),
  drinks('Drinks'),
  pantry('Pantry');

  const DealCategory(this.label);

  final String label;
}

enum DealStatus {
  open('Open'),
  fillingFast('Filling fast'),
  full('Full');

  const DealStatus(this.label);

  final String label;
}
