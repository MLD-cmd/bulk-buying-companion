import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/notification_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_notification.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'derives notifications from the current hub deals and participants',
    () async {
      final repository = DerivedNotificationRepository(
        dealRepository: _DealStub([
          _deal(id: 'rice', availableSlots: 0),
          _deal(id: 'water', purchasedAt: DateTime(2026, 7, 16)),
        ]),
        reservationRepository: _ReservationStub({
          'rice': [
            _reservation(dealId: 'rice', userId: 'host', isHost: true),
            _reservation(dealId: 'rice', userId: 'ana'),
          ],
          'water': [
            _reservation(dealId: 'water', userId: 'host', isHost: true),
            _reservation(dealId: 'water', userId: 'ana', paidAt: _now),
          ],
        }),
      );

      final notifications = await repository.getNotifications(
        hubId: 'colon',
        currentUserId: 'ana',
      );

      expect(notifications.map((item) => item.kind), [
        DealNotificationKind.pickupReminder,
        DealNotificationKind.paymentReminder,
        DealNotificationKind.dealFull,
      ]);
    },
  );
}

final _now = DateTime(2026, 7, 16);

Deal _deal({
  required String id,
  int availableSlots = 1,
  DateTime? purchasedAt,
}) {
  return Deal(
    id: id,
    hubId: 'colon',
    title: id == 'rice' ? 'Rice Sack' : 'Water Case',
    createdBy: 'host',
    hostName: 'Marco Villanueva',
    category: DealCategory.grocery,
    totalPrice: 300,
    amount: 25,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: 2,
    pickupLocation: 'Campus Gate',
    purchasedAt: purchasedAt,
    paidCount: 1,
  );
}

Reservation _reservation({
  required String dealId,
  required String userId,
  bool isHost = false,
  DateTime? paidAt,
}) {
  return Reservation(
    dealId: dealId,
    userId: userId,
    isHost: isHost,
    reservedAt: _now,
    paidAt: paidAt,
  );
}

class _DealStub implements DealRepository {
  const _DealStub(this.deals);

  final List<Deal> deals;

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<List<Deal>> getDeals(String hubId) async => deals;
}

class _ReservationStub implements ReservationRepository {
  const _ReservationStub(this.participantsByDeal);

  final Map<String, List<Reservation>> participantsByDeal;

  @override
  Future<Deal> cancelDeal(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> cancelReservation(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Reservation>> getParticipants(String dealId) async {
    return participantsByDeal[dealId] ?? const [];
  }

  @override
  Future<Deal> markPurchased(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> reserveSlot(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> setPaid(String dealId, String userId, {required bool paid}) {
    throw UnimplementedError();
  }
}
