import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_notification.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notifies the host when students reserve slots', () {
    final notifications = DealNotificationBuilder().build(
      currentUserId: 'host',
      deals: [_deal()],
      participantsByDeal: {
        'rice': [
          _reservation(userId: 'host', isHost: true, paidAt: _now),
          _reservation(userId: 'ana'),
          _reservation(userId: 'bea'),
        ],
      },
    );

    expect(
      notifications,
      contains(
        isA<DealNotification>()
            .having(
              (item) => item.kind,
              'kind',
              DealNotificationKind.reservationUpdate,
            )
            .having((item) => item.title, 'title', 'New slots reserved')
            .having(
              (item) => item.message,
              'message',
              contains('2 students have reserved Rice Sack'),
            ),
      ),
    );
  });

  test('notifies participants when their deal is full', () {
    final notifications = DealNotificationBuilder().build(
      currentUserId: 'ana',
      deals: [_deal(availableSlots: 0)],
      participantsByDeal: {
        'rice': [
          _reservation(userId: 'host', isHost: true, paidAt: _now),
          _reservation(userId: 'ana'),
          _reservation(userId: 'bea'),
        ],
      },
    );

    expect(
      notifications,
      contains(
        isA<DealNotification>()
            .having((item) => item.kind, 'kind', DealNotificationKind.dealFull)
            .having((item) => item.title, 'title', 'Deal is full')
            .having(
              (item) => item.message,
              'message',
              contains('Rice Sack is full'),
            ),
      ),
    );
  });

  test('reminds unpaid participants to pay for their slot', () {
    final notifications = DealNotificationBuilder().build(
      currentUserId: 'ana',
      deals: [_deal(availableSlots: 0, closesAt: DateTime(2026, 7, 20))],
      participantsByDeal: {
        'rice': [
          _reservation(userId: 'host', isHost: true, paidAt: _now),
          _reservation(userId: 'ana'),
          _reservation(userId: 'bea', paidAt: _now),
        ],
      },
    );

    expect(
      notifications,
      contains(
        isA<DealNotification>()
            .having(
              (item) => item.kind,
              'kind',
              DealNotificationKind.paymentReminder,
            )
            .having((item) => item.title, 'title', 'Payment reminder')
            .having((item) => item.message, 'message', contains('Pay P100'))
            .having(
              (item) => item.message,
              'message',
              contains('before 7/20/2026'),
            ),
      ),
    );
  });

  test('reminds participants to pick up bought items', () {
    final notifications = DealNotificationBuilder().build(
      currentUserId: 'ana',
      deals: [_deal(purchasedAt: _now)],
      participantsByDeal: {
        'rice': [
          _reservation(userId: 'host', isHost: true, paidAt: _now),
          _reservation(userId: 'ana', paidAt: _now),
        ],
      },
    );

    expect(
      notifications,
      contains(
        isA<DealNotification>()
            .having(
              (item) => item.kind,
              'kind',
              DealNotificationKind.pickupReminder,
            )
            .having((item) => item.title, 'title', 'Pickup reminder')
            .having(
              (item) => item.message,
              'message',
              'Pick up Rice Sack at Campus Gate.',
            ),
      ),
    );
  });

  test('notifies participants when a deal is cancelled', () {
    final notifications = DealNotificationBuilder().build(
      currentUserId: 'ana',
      deals: [_deal(cancelledAt: _now)],
      participantsByDeal: {
        'rice': [
          _reservation(userId: 'host', isHost: true, paidAt: _now),
          _reservation(userId: 'ana', paidAt: _now),
        ],
      },
    );

    expect(
      notifications,
      contains(
        isA<DealNotification>()
            .having(
              (item) => item.kind,
              'kind',
              DealNotificationKind.cancellation,
            )
            .having((item) => item.title, 'title', 'Deal cancelled')
            .having(
              (item) => item.message,
              'message',
              contains('Rice Sack was cancelled'),
            ),
      ),
    );
  });
}

final _now = DateTime(2026, 7, 16);

Deal _deal({
  int availableSlots = 1,
  DateTime? closesAt,
  DateTime? purchasedAt,
  DateTime? cancelledAt,
}) {
  return Deal(
    id: 'rice',
    hubId: 'colon',
    title: 'Rice Sack',
    createdBy: 'host',
    hostName: 'Marco Villanueva',
    category: DealCategory.grocery,
    totalPrice: 300,
    amount: 25,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: 3,
    pickupLocation: 'Campus Gate',
    closesAt: closesAt,
    purchasedAt: purchasedAt,
    cancelledAt: cancelledAt,
    paidCount: 1,
  );
}

Reservation _reservation({
  required String userId,
  bool isHost = false,
  DateTime? paidAt,
  DateTime? collectedAt,
}) {
  return Reservation(
    dealId: 'rice',
    userId: userId,
    isHost: isHost,
    reservedAt: _now,
    paidAt: paidAt,
    collectedAt: collectedAt,
  );
}
