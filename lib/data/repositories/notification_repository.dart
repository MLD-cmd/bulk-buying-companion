import '../../models/deal_notification.dart';
import '../../models/reservation.dart';
import 'deal_repository.dart';
import 'reservation_repository.dart';

abstract class NotificationRepository {
  Future<List<DealNotification>> getNotifications({
    required String hubId,
    required String currentUserId,
  });
}

class DerivedNotificationRepository implements NotificationRepository {
  DerivedNotificationRepository({
    required DealRepository dealRepository,
    required ReservationRepository reservationRepository,
    DealNotificationBuilder? builder,
  }) : _dealRepository = dealRepository,
       _reservationRepository = reservationRepository,
       _builder = builder ?? DealNotificationBuilder();

  final DealRepository _dealRepository;
  final ReservationRepository _reservationRepository;
  final DealNotificationBuilder _builder;

  @override
  Future<List<DealNotification>> getNotifications({
    required String hubId,
    required String currentUserId,
  }) async {
    final deals = await _dealRepository.getDeals(hubId);
    final participantLists = await Future.wait(
      deals.map((deal) => _reservationRepository.getParticipants(deal.id)),
    );

    final participantsByDeal = <String, List<Reservation>>{};
    for (var index = 0; index < deals.length; index += 1) {
      participantsByDeal[deals[index].id] = participantLists[index];
    }

    return _builder.build(
      currentUserId: currentUserId,
      deals: deals,
      participantsByDeal: participantsByDeal,
    );
  }
}
