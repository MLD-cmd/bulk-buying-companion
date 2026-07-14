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
}

/// Raised when a slot cannot be claimed or released. The message is user-facing.
class ReservationFailure implements Exception {
  const ReservationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class SupabaseReservationGateway {
  Future<List<Map<String, dynamic>>> getParticipants(String dealId);

  Future<Map<String, dynamic>> reserveSlot(String dealId);

  Future<Map<String, dynamic>> cancelReservation(String dealId);
}

class PostgrestSupabaseReservationGateway
    implements SupabaseReservationGateway {
  PostgrestSupabaseReservationGateway(this._client);

  final SupabaseClient _client;

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
  Future<List<Map<String, dynamic>>> getParticipants(String dealId) async {
    final rows = await _client
        .from('deal_participants')
        .select()
        .eq('deal_id', dealId)
        .order('reserved_at');
    return List<Map<String, dynamic>>.from(rows);
  }
}

class SupabaseReservationRepository implements ReservationRepository {
  SupabaseReservationRepository({required SupabaseReservationGateway gateway})
    : _gateway = gateway;

  final SupabaseReservationGateway _gateway;

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

  Reservation _reservationFromRow(Map<String, dynamic> row) {
    return Reservation(
      dealId: row['deal_id'] as String,
      userId: row['user_id'] as String,
      studentName: row['student_name'] as String?,
      isHost: row['is_host'] as bool? ?? false,
      reservedAt: DateTime.parse(row['reserved_at'] as String).toLocal(),
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
      _ => 'Could not update your slot. Please try again.',
    };
  }
}

/// In-memory stand-in that obeys the same rules as the database, so ViewModel
/// tests pass or fail for the same reasons production would.
class MockReservationRepository implements ReservationRepository {
  MockReservationRepository({required Deal deal, required this.currentUserId})
    : _deal = deal,
      _holders = {
        // Every deal has its host in it, exactly as the trigger guarantees.
        if (deal.createdBy != null) deal.createdBy!,
      };

  Deal _deal;
  final Set<String> _holders;
  final String currentUserId;

  Deal get deal => _deal;

  @override
  Future<List<Reservation>> getParticipants(String dealId) async {
    return _holders
        .map(
          (userId) => Reservation(
            dealId: dealId,
            userId: userId,
            studentName: userId == _deal.createdBy ? 'Marco Villanueva' : null,
            isHost: userId == _deal.createdBy,
            reservedAt: DateTime(2026, 7, 14),
          ),
        )
        .toList();
  }

  @override
  Future<Deal> reserveSlot(String dealId) async {
    if (_holders.contains(currentUserId)) {
      throw const ReservationFailure('You already have a slot in this deal.');
    }
    if (_deal.availableSlots == 0) {
      throw const ReservationFailure('This deal just filled up.');
    }

    _holders.add(currentUserId);
    _deal = _copyWithSlots(_deal.availableSlots - 1);
    return _deal;
  }

  @override
  Future<Deal> cancelReservation(String dealId) async {
    if (currentUserId == _deal.createdBy) {
      throw const ReservationFailure(
        'You are organising this buy, so your slot cannot be cancelled.',
      );
    }
    final closesAt = _deal.closesAt;
    if (closesAt != null && !closesAt.isAfter(DateTime.now())) {
      throw const ReservationFailure(
        'The deadline has passed, so slots are locked.',
      );
    }
    if (!_holders.remove(currentUserId)) {
      throw const ReservationFailure('You do not have a slot in this deal.');
    }

    _deal = _copyWithSlots(_deal.availableSlots + 1);
    return _deal;
  }

  Deal _copyWithSlots(int availableSlots) {
    return Deal(
      id: _deal.id,
      hubId: _deal.hubId,
      title: _deal.title,
      description: _deal.description,
      createdBy: _deal.createdBy,
      hostName: _deal.hostName,
      category: _deal.category,
      totalPrice: _deal.totalPrice,
      quantity: _deal.quantity,
      availableSlots: availableSlots,
      totalSlots: _deal.totalSlots,
      pickupLocation: _deal.pickupLocation,
      status: _deal.status,
      closesAt: _deal.closesAt,
    );
  }
}
