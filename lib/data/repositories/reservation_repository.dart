import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/deal.dart';
import '../../models/reservation.dart';
import 'deal_repository.dart';

/// Claiming and releasing one slot of a deal. Backed by
/// [MockReservationRepository] in tests and [SupabaseReservationRepository] in
/// production; the ViewModel never depends on the concrete implementation.
abstract class ReservationRepository {
  Future<List<Reservation>> getParticipants(String dealId);

  /// Returns the deal as it stands after the claim, so the caller never has to
  /// guess the new slot count.
  Future<Deal> reserveSlot(String dealId);

  Future<Deal> cancelReservation(String dealId);

  /// The host's four levers. Each returns the deal as it now stands, so the
  /// caller never has to guess the new status.
  ///
  /// Host-only, enforced in Postgres — a student who could mark themselves paid
  /// could send the host out to spend money on a promise.
  Future<Deal> setPaid(String dealId, String userId, {required bool paid});

  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  });

  Future<Deal> markPurchased(String dealId);

  Future<Deal> cancelDeal(String dealId);
}

class DealDetailsSnapshot {
  const DealDetailsSnapshot({required this.deal, required this.participants});

  final Deal deal;
  final List<Reservation> participants;
}

abstract class RealtimeReservationRepository {
  Stream<DealDetailsSnapshot> watchDealDetails(Deal deal);
}

/// Answers "which of these deals is this student in?" in one read.
///
/// Optional, like [RealtimeReservationRepository]: a caller without it has to
/// ask per deal, pulling down every participant of every deal to look for one
/// id. The profile's deal history asks this on every realtime push, so the
/// per-deal walk is a read per deal per push.
abstract class BatchReservationRepository {
  Future<Set<String>> getDealIdsWithSlotFor(
    String userId,
    List<String> dealIds,
  );
}

/// Raised when a slot cannot be claimed or released. The message is user-facing.
class ReservationFailure implements Exception {
  const ReservationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class SupabaseReservationGateway {
  Future<Map<String, dynamic>> getDeal(String dealId);

  Future<List<Map<String, dynamic>>> getParticipants(String dealId);

  /// The ids among [dealIds] that [userId] holds a slot in.
  Future<Set<String>> getHeldDealIds(String userId, List<String> dealIds);

  Future<Map<String, dynamic>> reserveSlot(String dealId);

  Future<Map<String, dynamic>> cancelReservation(String dealId);

  Future<Map<String, dynamic>> setParticipantPaid(
    String dealId,
    String userId,
    bool paid,
  );

  Future<Map<String, dynamic>> setParticipantCollected(
    String dealId,
    String userId,
    bool collected,
  );

  Future<Map<String, dynamic>> markPurchased(String dealId);

  Future<Map<String, dynamic>> cancelDeal(String dealId);
}

class PostgrestSupabaseReservationGateway
    implements SupabaseReservationGateway {
  PostgrestSupabaseReservationGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> getDeal(String dealId) async {
    final row = await _client
        .from('deal_feed')
        .select()
        .eq('id', dealId)
        .single();
    return Map<String, dynamic>.from(row);
  }

  /// Both mutations go through an RPC rather than a table write: the
  /// reservation and the slot count have to move together, in one transaction,
  /// or two students can claim the same last slot.
  @override
  Future<Map<String, dynamic>> reserveSlot(String dealId) async {
    final row = await _client.rpc(
      'reserve_slot',
      params: {'p_deal_id': dealId},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> cancelReservation(String dealId) async {
    final row = await _client.rpc(
      'cancel_reservation',
      params: {'p_deal_id': dealId},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> setParticipantPaid(
    String dealId,
    String userId,
    bool paid,
  ) async {
    final row = await _client.rpc(
      'set_participant_paid',
      params: {'p_deal_id': dealId, 'p_user_id': userId, 'p_paid': paid},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> setParticipantCollected(
    String dealId,
    String userId,
    bool collected,
  ) async {
    final row = await _client.rpc(
      'set_participant_collected',
      params: {
        'p_deal_id': dealId,
        'p_user_id': userId,
        'p_collected': collected,
      },
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> markPurchased(String dealId) async {
    final row = await _client.rpc(
      'mark_purchased',
      params: {'p_deal_id': dealId},
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<Map<String, dynamic>> cancelDeal(String dealId) async {
    final row = await _client.rpc('cancel_deal', params: {'p_deal_id': dealId});
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> getParticipants(String dealId) async {
    final rows = await _client
        .from('deal_participants')
        .select()
        .eq('deal_id', dealId)
        .order('reserved_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Set<String>> getHeldDealIds(
    String userId,
    List<String> dealIds,
  ) async {
    // Only the ids, only this student's rows: the caller is asking which deals
    // they are in, not who else is in them.
    final rows = await _client
        .from('deal_participants')
        .select('deal_id')
        .eq('user_id', userId)
        .inFilter('deal_id', dealIds);
    return {
      for (final row in List<Map<String, dynamic>>.from(rows))
        row['deal_id'] as String,
    };
  }
}

abstract class ReservationInvalidationSource {
  Stream<void> watchDeal(String dealId);
}

class SupabaseReservationInvalidationSource
    implements ReservationInvalidationSource {
  SupabaseReservationInvalidationSource(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> watchDeal(String dealId) {
    late final RealtimeChannel channel;
    final controller = StreamController<void>();

    void invalidate(PostgresChangePayload _) {
      if (!controller.isClosed) controller.add(null);
    }

    controller.onListen = () {
      channel = _client
          .channel(
            'deal-details:$dealId:${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'deals',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: dealId,
            ),
            callback: invalidate,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'deal_reservations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'deal_id',
              value: dealId,
            ),
            callback: invalidate,
          )
          .subscribe((status, error) {
            if (controller.isClosed) return;
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              controller.addError(
                error ?? const RealtimeReservationSubscriptionFailure(),
              );
            }
          });
    };

    controller.onCancel = () async {
      await channel.unsubscribe();
    };
    return controller.stream;
  }
}

class RealtimeReservationSubscriptionFailure implements Exception {
  const RealtimeReservationSubscriptionFailure();

  @override
  String toString() => 'Realtime reservation subscription failed.';
}

class SupabaseReservationRepository
    implements
        ReservationRepository,
        RealtimeReservationRepository,
        BatchReservationRepository {
  SupabaseReservationRepository({
    required SupabaseReservationGateway gateway,
    ReservationInvalidationSource? invalidationSource,
  }) : _gateway = gateway,
       _invalidationSource = invalidationSource;

  final SupabaseReservationGateway _gateway;
  final ReservationInvalidationSource? _invalidationSource;

  @override
  Stream<DealDetailsSnapshot> watchDealDetails(Deal deal) async* {
    yield await _getSnapshot(deal);

    final invalidationSource = _invalidationSource;
    if (invalidationSource == null) return;

    await for (final _ in invalidationSource.watchDeal(deal.id)) {
      yield await _getSnapshot(deal);
    }
  }

  /// One read for the whole history, rather than the base class's read per
  /// deal. The profile re-runs this on every realtime push.
  @override
  Future<Set<String>> getDealIdsWithSlotFor(
    String userId,
    List<String> dealIds,
  ) async {
    if (dealIds.isEmpty) return const <String>{};
    try {
      return await _gateway.getHeldDealIds(userId, dealIds);
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> reserveSlot(String dealId) async {
    try {
      return dealFromRow(await _gateway.reserveSlot(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> cancelReservation(String dealId) async {
    try {
      return dealFromRow(await _gateway.cancelReservation(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> setPaid(
    String dealId,
    String userId, {
    required bool paid,
  }) async {
    try {
      return dealFromRow(
        await _gateway.setParticipantPaid(dealId, userId, paid),
      );
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  }) async {
    try {
      return dealFromRow(
        await _gateway.setParticipantCollected(dealId, userId, collected),
      );
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> markPurchased(String dealId) async {
    try {
      return dealFromRow(await _gateway.markPurchased(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<Deal> cancelDeal(String dealId) async {
    try {
      return dealFromRow(await _gateway.cancelDeal(dealId));
    } on PostgrestException catch (error) {
      throw ReservationFailure(_messageFor(error));
    }
  }

  @override
  Future<List<Reservation>> getParticipants(String dealId) async {
    final rows = await _gateway.getParticipants(dealId);
    final participants = rows.map(_reservationFromRow).toList();
    // The organiser leads the list: they are the person everyone else is
    // relying on.
    participants.sort((a, b) {
      if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
      return a.reservedAt.compareTo(b.reservedAt);
    });
    return participants;
  }

  Future<DealDetailsSnapshot> _getSnapshot(Deal fallbackDeal) async {
    Deal deal;
    try {
      deal = dealFromRow(await _gateway.getDeal(fallbackDeal.id));
    } catch (_) {
      deal = fallbackDeal;
    }
    return DealDetailsSnapshot(
      deal: deal,
      participants: await getParticipants(fallbackDeal.id),
    );
  }

  Reservation _reservationFromRow(Map<String, dynamic> row) {
    final paidAt = row['paid_at'] as String?;
    final collectedAt = row['collected_at'] as String?;
    return Reservation(
      dealId: row['deal_id'] as String,
      userId: row['user_id'] as String,
      studentName: row['student_name'] as String?,
      isHost: row['is_host'] as bool? ?? false,
      reservedAt: DateTime.parse(row['reserved_at'] as String).toLocal(),
      paidAt: paidAt == null ? null : DateTime.parse(paidAt).toLocal(),
      collectedAt: collectedAt == null
          ? null
          : DateTime.parse(collectedAt).toLocal(),
    );
  }

  /// These codes are raised by the reserve_slot / cancel_reservation functions;
  /// see the slot reservation migration.
  String _messageFor(PostgrestException error) {
    return switch (error.code) {
      'P0001' => 'This deal just filled up.',
      '23505' => 'You already have a slot in this deal.',
      'P0003' =>
        'You are organising this buy, so your slot cannot be cancelled.',
      'P0004' => 'The deadline has passed, so slots are locked.',
      'P0005' => 'You do not have a slot in this deal.',
      'P0002' => 'That deal no longer exists.',
      '42501' => 'You can only reserve slots in your own hub.',
      'P0006' => 'This deal is closed.',
      'P0007' => 'The goods have not been bought yet.',
      'P0008' => 'You have already marked this bought.',
      'P0009' => 'This deal is already cancelled.',
      'P0010' => 'This deal is finished, so it cannot be cancelled.',
      'P0011' =>
        'You have already paid for this slot. Ask the host before you pull out.',
      'P0012' => 'Only the host can do that.',
      'P0013' => 'The host slot is always paid.',
      _ => 'Could not update your slot. Please try again.',
    };
  }
}

/// In-memory stand-in that obeys the same rules as the database, so ViewModel
/// tests pass or fail for the same reasons production would.
class MockReservationRepository
    implements ReservationRepository, RealtimeReservationRepository {
  MockReservationRepository({required Deal deal, required this.currentUserId})
    : _deal = deal,
      _holders = {
        // Every deal has its host in it, exactly as the trigger guarantees.
        if (deal.createdBy != null) deal.createdBy!,
      },
      // The host's slot is paid from the moment the deal exists.
      _paid = {if (deal.createdBy != null) deal.createdBy!},
      _collected = {};

  Deal _deal;
  final Set<String> _holders;
  final Set<String> _paid;
  final Set<String> _collected;
  final String currentUserId;

  Deal get deal => _deal;

  @override
  Stream<DealDetailsSnapshot> watchDealDetails(Deal deal) async* {
    yield DealDetailsSnapshot(
      deal: _deal,
      participants: await getParticipants(deal.id),
    );
  }

  /// Test seam: stand in for another student. reserveSlot() always acts as
  /// currentUserId, and a deal with three students in it cannot be built from
  /// three separate mocks — they would each hold a different deal.
  Future<Deal> reserveSlotFor(String userId) async {
    if (_holders.contains(userId)) {
      throw const ReservationFailure('You already have a slot in this deal.');
    }
    if (_deal.availableSlots == 0) {
      throw const ReservationFailure('This deal just filled up.');
    }
    _holders.add(userId);
    return _sync(availableSlots: _deal.availableSlots - 1);
  }

  /// Test seam: release another student's slot. cancelReservation() always acts
  /// as currentUserId, so a test standing in for several students in one deal
  /// releases them by name here.
  Future<Deal> cancelReservationFor(String userId) async {
    if (userId == _deal.createdBy) {
      throw const ReservationFailure(
        'You are organising this buy, so your slot cannot be cancelled.',
      );
    }
    if (_paid.contains(userId)) {
      throw const ReservationFailure(
        'You have already paid for this slot. Ask the host before you pull out.',
      );
    }
    if (!_holders.remove(userId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }
    _collected.remove(userId);
    return _sync(availableSlots: _deal.availableSlots + 1);
  }

  /// Test seam: record a payment directly, bypassing the host-only guard that
  /// setPaid enforces, so a test can build a student's own view of a deal they
  /// have already paid for. Not a production path — nothing outside tests calls
  /// this, and the host-only rule is proven against the real setPaid.
  Future<Deal> markPaidForTest(String userId) async {
    if (!_holders.contains(userId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }
    _paid.add(userId);
    return _sync();
  }

  @override
  Future<List<Reservation>> getParticipants(String dealId) async {
    return _holders
        .map(
          (userId) => Reservation(
            dealId: dealId,
            userId: userId,
            studentName: _displayNameFor(userId),
            isHost: userId == _deal.createdBy,
            reservedAt: DateTime(2026, 7, 14),
            paidAt: _paid.contains(userId) ? DateTime(2026, 7, 14) : null,
            collectedAt: _collected.contains(userId)
                ? DateTime(2026, 7, 15)
                : null,
          ),
        )
        .toList();
  }

  String? _displayNameFor(String userId) {
    if (userId == _deal.createdBy) return _deal.hostName ?? 'Marco Villanueva';
    if (userId == 'user-2') return 'Jayrald B. Tajanlangit';
    if (userId.trim().isEmpty) return null;
    return userId;
  }

  @override
  Future<Deal> reserveSlot(String dealId) async {
    if (_deal.cancelledAt != null || _deal.purchasedAt != null) {
      throw const ReservationFailure('This deal is closed.');
    }
    return reserveSlotFor(currentUserId);
  }

  @override
  Future<Deal> cancelReservation(String dealId) async {
    if (_deal.cancelledAt != null || _deal.purchasedAt != null) {
      throw const ReservationFailure('This deal is closed.');
    }
    final closesAt = _deal.closesAt;
    if (closesAt != null && !closesAt.isAfter(DateTime.now())) {
      throw const ReservationFailure(
        'The deadline has passed, so slots are locked.',
      );
    }
    return cancelReservationFor(currentUserId);
  }

  @override
  Future<Deal> setPaid(
    String dealId,
    String userId, {
    required bool paid,
  }) async {
    _requireHost();
    _requireNotCancelled();
    if (!_holders.contains(userId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }
    if (userId == _deal.createdBy && !paid) {
      throw const ReservationFailure('The host slot is always paid.');
    }
    paid ? _paid.add(userId) : _paid.remove(userId);
    return _sync();
  }

  @override
  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  }) async {
    _requireHost();
    _requireNotCancelled();
    if (_deal.purchasedAt == null) {
      throw const ReservationFailure('The goods have not been bought yet.');
    }
    if (!_holders.contains(userId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }
    collected ? _collected.add(userId) : _collected.remove(userId);
    return _sync();
  }

  @override
  Future<Deal> markPurchased(String dealId) async {
    _requireHost();
    _requireNotCancelled();
    if (_deal.purchasedAt != null) {
      throw const ReservationFailure('You have already marked this bought.');
    }
    // The host is holding the goods, so their own share is collected.
    final host = _deal.createdBy;
    if (host != null) _collected.add(host);
    return _sync(purchasedAt: DateTime(2026, 7, 16));
  }

  @override
  Future<Deal> cancelDeal(String dealId) async {
    _requireHost();
    if (_deal.cancelledAt != null) {
      throw const ReservationFailure('This deal is already cancelled.');
    }
    if (_deal.status == DealStatus.completed) {
      throw const ReservationFailure(
        'This deal is finished, so it cannot be cancelled.',
      );
    }
    return _sync(cancelledAt: DateTime(2026, 7, 16));
  }

  void _requireHost() {
    if (currentUserId != _deal.createdBy) {
      throw const ReservationFailure('Only the host can do that.');
    }
  }

  void _requireNotCancelled() {
    if (_deal.cancelledAt != null) {
      throw const ReservationFailure('This deal is closed.');
    }
  }

  /// The counts on a Deal come from deal_feed, which recounts the reservation
  /// rows on every read. The mock recounts too, rather than tracking a second
  /// copy that could drift from the sets above.
  Deal _sync({
    int? availableSlots,
    DateTime? purchasedAt,
    DateTime? cancelledAt,
  }) {
    _deal = _deal.copyWith(
      availableSlots: availableSlots,
      purchasedAt: purchasedAt,
      cancelledAt: cancelledAt,
      paidCount: _paid.length,
      collectedCount: _collected.length,
    );
    return _deal;
  }
}
