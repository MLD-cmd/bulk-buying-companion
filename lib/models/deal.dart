import 'dart:math' as math;

import 'cost_split.dart';
import 'deal_unit.dart';
import 'physical_share.dart';

/// A bulk-buying deal posted within a hub.
class Deal {
  const Deal({
    required this.id,
    required this.hubId,
    required this.title,
    required this.category,
    required this.totalPrice,
    required this.amount,
    required this.unit,
    required this.availableSlots,
    required this.totalSlots,
    required this.pickupLocation,
    this.description,
    this.paymentMethod,
    this.paymentAccountName,
    this.paymentAccountHandle,
    this.paymentInstructions,
    this.closesAt,
    this.createdBy,
    this.hostName,
    this.purchasedAt,
    this.cancelledAt,
    this.paidCount = 0,
    this.collectedCount = 0,
  });

  final String id;
  final String hubId;
  final String title;

  /// The student organising the buy. [createdBy] is null on the deals seeded
  /// into the mock; [hostName] comes from the deal_feed view and stays null
  /// when the host has no profile row, or on the Deal returned straight from
  /// an insert (that row is the raw deals table, which has no host_name).
  final String? createdBy;
  final String? hostName;

  /// What to call the host when their name is unknown, rather than leaving a
  /// gap where a person should be.
  String get hostLabel => hostName?.trim().isNotEmpty == true
      ? hostName!.trim()
      : 'A student in this hub';

  /// Optional detail the poster adds: brand, size, where they are buying it.
  final String? description;
  final DealCategory category;

  /// Cost of the whole bulk buy, before it is split. The per-share price the
  /// student actually pays is derived from this — see [pricePerShare].
  final double totalPrice;

  /// How much the bulk buy covers, and in what. The unit also decides whether
  /// the goods can be divided at all — see [PhysicalShare].
  final double amount;
  final DealUnit unit;

  final int availableSlots;
  final int totalSlots;
  final String pickupLocation;
  final String? paymentMethod;
  final String? paymentAccountName;
  final String? paymentAccountHandle;
  final String? paymentInstructions;
  final DateTime? closesAt;

  /// The host has bought the goods. Set by mark_purchased; never cleared.
  final DateTime? purchasedAt;

  /// The host called the deal off. Set by cancel_deal; never cleared.
  final DateTime? cancelledAt;

  /// How many of the students in this deal have handed the host their share,
  /// and how many have taken their goods away. Both come from deal_feed.
  final int paidCount;
  final int collectedCount;

  /// Every peso figure on a deal comes from here, so the card, the details
  /// screen and the poster's preview cannot disagree with each other.
  ///
  /// Clamped, not strict: a Deal is built straight from a database row, and
  /// this getter runs inside build. A row with no slots or no price is bad
  /// data, but it must not throw and red-screen the whole feed on the way out.
  CostSplit get costSplit =>
      CostSplit.clamped(totalPrice: totalPrice, slots: totalSlots);

  /// What one student physically receives. Sits beside [costSplit]: together
  /// they answer the two questions a student has — what do I pay, what do I get.
  PhysicalShare get physicalShare =>
      PhysicalShare.from(amount: amount, unit: unit, slots: totalSlots);

  double get pricePerShare => costSplit.pricePerShare;

  bool get hasPaymentInfo =>
      _hasText(paymentMethod) ||
      _hasText(paymentAccountName) ||
      _hasText(paymentAccountHandle) ||
      _hasText(paymentInstructions);

  /// Every claimed slot is a student in the buy. The reserve/cancel RPCs move
  /// available_slots and the reservation rows together in one transaction, so
  /// this cannot drift — and storing it separately would be a second copy of a
  /// number that already exists.
  int get participantCount => totalSlots - availableSlots;

  /// Derived, never stored. The column this replaces was updated by nothing, so
  /// a full deal still showed an "Open" badge. Here there is no second copy to
  /// keep in step: a student leaving a ready-to-purchase deal reopens it with no
  /// code path written to make that happen.
  DealStatus get status {
    if (cancelledAt != null) return DealStatus.cancelled;

    if (purchasedAt != null) {
      // Purchase gates both, so goods that were never bought cannot be reported
      // as collected.
      return participantCount > 0 && collectedCount >= participantCount
          ? DealStatus.completed
          : DealStatus.readyForPickup;
    }

    if (availableSlots == 0) {
      return participantCount > 0 && paidCount >= participantCount
          ? DealStatus.readyToPurchase
          : DealStatus.full;
    }

    return DealStatus.open;
  }

  /// A label on an open deal that is nearly full, not a state of its own.
  ///
  /// The last slot always counts: on a 3-way split, one seat left is as urgent
  /// as a deal gets, and a flat quarter rule would stay silent through it.
  bool get isFillingFast =>
      status == DealStatus.open &&
      (availableSlots == 1 || availableSlots * 4 <= totalSlots);

  /// What the badge reads.
  String get statusLabel => isFillingFast ? 'Filling fast' : status.label;

  /// The host's own slot is marked paid the moment the deal exists — they
  /// cannot pay themselves — so it is not money they are holding for anyone.
  ///
  /// Bounded on both sides rather than trusted: this feeds the peso figure in
  /// the cancel dialog, and a Deal is built straight from a database row.
  /// [CostSplit.clamped] is here for the same reason.
  int get studentsWhoPaid {
    final students = math.max(0, participantCount - 1);
    return math.min(math.max(0, paidCount - 1), students);
  }

  /// What the host would have to hand back if they cancelled now.
  double get amountHeld => studentsWhoPaid * pricePerShare;

  /// Copies only the facts the lifecycle moves; everything else a deal is
  /// published with stays put.
  ///
  /// [purchasedAt] and [cancelledAt] are set once and cannot be cleared through
  /// here — passing null leaves them as they were, rather than un-buying or
  /// un-cancelling the deal, because nothing in the app ever does either.
  Deal copyWith({
    int? availableSlots,
    DateTime? purchasedAt,
    DateTime? cancelledAt,
    int? paidCount,
    int? collectedCount,
  }) {
    return Deal(
      id: id,
      hubId: hubId,
      title: title,
      description: description,
      createdBy: createdBy,
      hostName: hostName,
      category: category,
      totalPrice: totalPrice,
      amount: amount,
      unit: unit,
      availableSlots: availableSlots ?? this.availableSlots,
      totalSlots: totalSlots,
      pickupLocation: pickupLocation,
      paymentMethod: paymentMethod,
      paymentAccountName: paymentAccountName,
      paymentAccountHandle: paymentAccountHandle,
      paymentInstructions: paymentInstructions,
      closesAt: closesAt,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      paidCount: paidCount ?? this.paidCount,
      collectedCount: collectedCount ?? this.collectedCount,
    );
  }

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
    required this.amount,
    required this.unit,
    required this.totalSlots,
    required this.pickupLocation,
    this.description,
    this.paymentMethod,
    this.paymentAccountName,
    this.paymentAccountHandle,
    this.paymentInstructions,
    this.closesAt,
  });

  final String hubId;
  final String title;
  final String? description;
  final DealCategory category;
  final double totalPrice;
  final double amount;
  final DealUnit unit;
  final int totalSlots;
  final String pickupLocation;
  final String? paymentMethod;
  final String? paymentAccountName;
  final String? paymentAccountHandle;
  final String? paymentInstructions;
  final DateTime? closesAt;
}

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

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
  full('Full'),
  readyToPurchase('Ready to purchase'),
  readyForPickup('Ready for pickup'),
  completed('Completed'),
  cancelled('Cancelled');

  const DealStatus(this.label);

  final String label;

  /// Completed and cancelled deals are not open business. The Split Board hides
  /// them unless they are asked for by name.
  bool get isFinished =>
      this == DealStatus.completed || this == DealStatus.cancelled;
}
