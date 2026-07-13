/// A bulk-buying deal posted within a hub.
class Deal {
  const Deal({
    required this.id,
    required this.hubId,
    required this.title,
    required this.priceLabel,
    required this.category,
    required this.availableSlots,
    required this.totalSlots,
    required this.pickupLocation,
    required this.status,
    this.closesAt,
  });

  final String id;
  final String hubId;
  final String title;
  final String priceLabel;
  final DealCategory category;
  final int availableSlots;
  final int totalSlots;
  final String pickupLocation;
  final DealStatus status;
  final DateTime? closesAt;

  String get availableSlotsLabel => '$availableSlots of $totalSlots slots open';

  String get deadlineLabel {
    final deadline = closesAt;
    if (deadline == null) {
      return 'Deadline TBD';
    }
    return 'Closes ${deadline.month}/${deadline.day}/${deadline.year}';
  }
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
