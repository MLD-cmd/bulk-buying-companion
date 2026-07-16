import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/deal_notification.dart';
import '../../models/reservation.dart';
import 'deal_repository.dart';
import 'reservation_repository.dart';

abstract class NotificationRepository {
  Future<List<DealNotification>> getNotifications({
    required String hubId,
    required String currentUserId,
  });

  Stream<List<DealNotification>> watchNotifications({
    required String hubId,
    required String currentUserId,
  }) async* {
    yield await getNotifications(hubId: hubId, currentUserId: currentUserId);
  }
}

abstract class NotificationInvalidationSource {
  Stream<void> watchHub(String hubId);
}

class SupabaseNotificationInvalidationSource
    implements NotificationInvalidationSource {
  SupabaseNotificationInvalidationSource(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> watchHub(String hubId) {
    late final RealtimeChannel channel;
    final controller = StreamController<void>();

    void invalidate(PostgresChangePayload _) {
      if (!controller.isClosed) controller.add(null);
    }

    controller.onListen = () {
      channel = _client
          .channel(
            'notifications:$hubId:${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'deals',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'hub_id',
              value: hubId,
            ),
            callback: invalidate,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'deal_reservations',
            callback: invalidate,
          )
          .subscribe((status, error) {
            if (controller.isClosed) return;
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              controller.addError(error ?? const RealtimeSubscriptionFailure());
            }
          });
    };

    controller.onCancel = () async {
      await channel.unsubscribe();
    };
    return controller.stream;
  }
}

class RealtimeSubscriptionFailure implements Exception {
  const RealtimeSubscriptionFailure();

  @override
  String toString() => 'Realtime notification subscription failed.';
}

class DerivedNotificationRepository implements NotificationRepository {
  DerivedNotificationRepository({
    required DealRepository dealRepository,
    required ReservationRepository reservationRepository,
    NotificationInvalidationSource? invalidationSource,
    DealNotificationBuilder? builder,
  }) : _dealRepository = dealRepository,
       _reservationRepository = reservationRepository,
       _invalidationSource = invalidationSource,
       _builder = builder ?? DealNotificationBuilder();

  final DealRepository _dealRepository;
  final ReservationRepository _reservationRepository;
  final NotificationInvalidationSource? _invalidationSource;
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

  @override
  Stream<List<DealNotification>> watchNotifications({
    required String hubId,
    required String currentUserId,
  }) async* {
    yield await getNotifications(hubId: hubId, currentUserId: currentUserId);

    final invalidationSource = _invalidationSource;
    if (invalidationSource == null) return;

    await for (final _ in invalidationSource.watchHub(hubId)) {
      yield await getNotifications(hubId: hubId, currentUserId: currentUserId);
    }
  }
}
