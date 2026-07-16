import 'deal.dart';
import 'reservation.dart';

enum DealNotificationKind {
  reservationUpdate,
  dealFull,
  paymentReminder,
  pickupReminder,
  itemCollected,
  cancellation,
}

class DealNotification {
  const DealNotification({
    required this.id,
    required this.dealId,
    required this.kind,
    required this.title,
    required this.message,
  });

  final String id;
  final String dealId;
  final DealNotificationKind kind;
  final String title;
  final String message;
}

class DealNotificationBuilder {
  List<DealNotification> build({
    required String currentUserId,
    required List<Deal> deals,
    required Map<String, List<Reservation>> participantsByDeal,
  }) {
    final notifications = <DealNotification>[];

    for (final deal in deals) {
      final participants = participantsByDeal[deal.id] ?? const [];
      final currentReservation = participants
          .where((participant) => participant.userId == currentUserId)
          .firstOrNull;
      final isHost = deal.createdBy == currentUserId;
      final holdsSlot = currentReservation != null;

      if (deal.status == DealStatus.cancelled && (isHost || holdsSlot)) {
        notifications.add(
          DealNotification(
            id: '${deal.id}-cancelled',
            dealId: deal.id,
            kind: DealNotificationKind.cancellation,
            title: 'Deal cancelled',
            message:
                '${deal.title} was cancelled. Check with ${deal.hostLabel} about refunds.',
          ),
        );
        continue;
      }

      if (currentReservation != null &&
          !currentReservation.isHost &&
          currentReservation.hasCollected &&
          deal.status != DealStatus.cancelled) {
        notifications.add(
          DealNotification(
            id: '${deal.id}-collected',
            dealId: deal.id,
            kind: DealNotificationKind.itemCollected,
            title: 'Item collected',
            message: '${deal.title} has been marked collected.',
          ),
        );
      }

      if (isHost) {
        final reservedStudents = participants
            .where((participant) => !participant.isHost)
            .length;
        if (reservedStudents > 0 && !deal.status.isFinished) {
          notifications.add(
            DealNotification(
              id: '${deal.id}-reservations',
              dealId: deal.id,
              kind: DealNotificationKind.reservationUpdate,
              title: reservedStudents == 1
                  ? 'New slot reserved'
                  : 'New slots reserved',
              message:
                  '$reservedStudents ${_studentLabel(reservedStudents)} have reserved ${deal.title}.',
            ),
          );
        }
      }

      if (!holdsSlot || currentReservation.isHost || deal.status.isFinished) {
        continue;
      }

      if (deal.availableSlots == 0 && deal.purchasedAt == null) {
        notifications.add(
          DealNotification(
            id: '${deal.id}-full',
            dealId: deal.id,
            kind: DealNotificationKind.dealFull,
            title: 'Deal is full',
            message:
                '${deal.title} is full. Wait for ${deal.hostLabel} to buy it.',
          ),
        );
      }

      if (!currentReservation.hasPaid && deal.purchasedAt == null) {
        notifications.add(
          DealNotification(
            id: '${deal.id}-payment',
            dealId: deal.id,
            kind: DealNotificationKind.paymentReminder,
            title: 'Payment reminder',
            message: _paymentMessage(deal),
          ),
        );
      }

      if (deal.purchasedAt != null && !currentReservation.hasCollected) {
        notifications.add(
          DealNotification(
            id: '${deal.id}-pickup',
            dealId: deal.id,
            kind: DealNotificationKind.pickupReminder,
            title: 'Pickup reminder',
            message: 'Pick up ${deal.title} at ${deal.pickupLocation}.',
          ),
        );
      }
    }

    notifications.sort(
      (a, b) => _priority(a.kind).compareTo(_priority(b.kind)),
    );
    return List.unmodifiable(notifications);
  }

  String _paymentMessage(Deal deal) {
    final amount = formatPeso(deal.pricePerShare);
    final deadline = deal.closesAt;
    if (deadline == null) {
      return 'Pay $amount for ${deal.title}.';
    }
    return 'Pay $amount for ${deal.title} before ${_dateLabel(deadline)}.';
  }

  String _dateLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';

  String _studentLabel(int count) => count == 1 ? 'student' : 'students';

  int _priority(DealNotificationKind kind) {
    return switch (kind) {
      DealNotificationKind.cancellation => 0,
      DealNotificationKind.itemCollected => 1,
      DealNotificationKind.pickupReminder => 2,
      DealNotificationKind.paymentReminder => 3,
      DealNotificationKind.dealFull => 4,
      DealNotificationKind.reservationUpdate => 5,
    };
  }
}
