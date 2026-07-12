/// A bulk-buying deal posted within a hub. This is the scaffold shape used
/// by the Split Board list; the deal-detail fields (price, available slots,
/// pickup location, status) are added on top of this by the deal-card work.
class Deal {
  const Deal({
    required this.id,
    required this.hubId,
    required this.title,
  });

  final String id;
  final String hubId;
  final String title;
}
