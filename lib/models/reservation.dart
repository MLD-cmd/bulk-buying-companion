/// One student's claim on one slot of a deal.
class Reservation {
  const Reservation({
    required this.dealId,
    required this.userId,
    required this.reservedAt,
    this.studentName,
    this.isHost = false,
    this.paidAt,
    this.collectedAt,
  });

  final String dealId;
  final String userId;
  final DateTime reservedAt;

  /// Comes from the deal_participants view, and stays null when the student
  /// has no profile row.
  final String? studentName;

  /// The student organising the buy. Their slot cannot be cancelled.
  final bool isHost;

  /// When this student handed the host their share. The host's own slot is paid
  /// from the moment the deal exists — they cannot pay themselves.
  final DateTime? paidAt;

  /// When this student took their goods away. Only ever set after the host has
  /// bought them.
  final DateTime? collectedAt;

  bool get hasPaid => paidAt != null;
  bool get hasCollected => collectedAt != null;

  /// What to call the student when their name is unknown, rather than leaving
  /// a gap where a person should be.
  String get displayName => studentName?.trim().isNotEmpty == true
      ? studentName!.trim()
      : 'A student in this hub';
}
