/// One student's claim on one slot of a deal.
class Reservation {
  const Reservation({
    required this.dealId,
    required this.userId,
    required this.reservedAt,
    this.studentName,
    this.isHost = false,
  });

  final String dealId;
  final String userId;
  final DateTime reservedAt;

  /// Comes from the deal_participants view, and stays null when the student
  /// has no profile row.
  final String? studentName;

  /// The student organising the buy. Their slot cannot be cancelled.
  final bool isHost;

  /// What to call the student when their name is unknown, rather than leaving
  /// a gap where a person should be.
  String get displayName => studentName?.trim().isNotEmpty == true
      ? studentName!.trim()
      : 'A student in this hub';
}
