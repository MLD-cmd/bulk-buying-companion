/// A bulk-buying deal posted within a hub.
class Deal {
  const Deal({
    required this.id,
    required this.hubId,
    required this.title,
    required this.priceLabel,
    required this.availableSlots,
    required this.totalSlots,
    required this.pickupLocation,
    required this.status,
  });

  final String id;
  final String hubId;
  final String title;
  final String priceLabel;
  final int availableSlots;
  final int totalSlots;
  final String pickupLocation;
  final DealStatus status;

  String get availableSlotsLabel => '$availableSlots of $totalSlots slots open';
}

enum DealStatus {
  open('Open'),
  fillingFast('Filling fast'),
  full('Full');

  const DealStatus(this.label);

  final String label;
}
