import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/deal.dart';

/// Split Board deal-feed contract. Backed by [MockDealRepository] in tests and
/// [SupabaseDealRepository] in production; the ViewModel never depends on the
/// concrete implementation.
abstract class DealRepository {
  Future<List<Deal>> getDeals(String hubId);

  Future<Deal> createDeal(DealDraft draft);
}

/// Raised when a deal cannot be published. The message is user-facing.
class DealFailure implements Exception {
  const DealFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// In-memory stand-in. Deals are stubbed per hub so the Split Board renders
/// with placeholder cards in tests.
class MockDealRepository implements DealRepository {
  MockDealRepository()
    : _dealsByHub = {
        'colon': [
          Deal(
            id: 'colon-rice',
            hubId: 'colon',
            title: '25kg Rice Sack — Split 5 ways',
            totalPrice: 900,
            quantity: 1,
            category: DealCategory.grocery,
            availableSlots: 3,
            totalSlots: 5,
            pickupLocation: 'USJR Main Gate',
            status: DealStatus.open,
            closesAt: DateTime(2026, 7, 16),
          ),
          Deal(
            id: 'colon-water',
            hubId: 'colon',
            title: 'Bottled Water Case (24pk)',
            totalPrice: 380,
            quantity: 24,
            category: DealCategory.drinks,
            availableSlots: 2,
            totalSlots: 4,
            pickupLocation: 'Colon Street Hub',
            status: DealStatus.fillingFast,
            closesAt: DateTime(2026, 7, 14),
          ),
          Deal(
            id: 'colon-detergent',
            hubId: 'colon',
            title: 'Laundry Detergent 6L',
            totalPrice: 360,
            quantity: 1,
            category: DealCategory.household,
            availableSlots: 0,
            totalSlots: 3,
            pickupLocation: 'Barangay Hall Lobby',
            status: DealStatus.full,
            closesAt: DateTime(2026, 7, 18),
          ),
        ],
        'magallanes': [
          Deal(
            id: 'magallanes-eggs',
            hubId: 'magallanes',
            title: 'Egg Tray (30s) — Split 3 ways',
            totalPrice: 255,
            quantity: 30,
            category: DealCategory.grocery,
            availableSlots: 1,
            totalSlots: 3,
            pickupLocation: 'Magallanes Residence Gate',
            status: DealStatus.fillingFast,
            closesAt: DateTime(2026, 7, 15),
          ),
          Deal(
            id: 'magallanes-coffee',
            hubId: 'magallanes',
            title: '3-in-1 Coffee Bulk Pack',
            totalPrice: 900,
            quantity: 60,
            category: DealCategory.pantry,
            availableSlots: 4,
            totalSlots: 6,
            pickupLocation: 'Tower A Lobby',
            status: DealStatus.open,
            closesAt: DateTime(2026, 7, 19),
          ),
        ],
      };

  final Map<String, List<Deal>> _dealsByHub;
  int _nextId = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) async {
    return List.unmodifiable(_dealsByHub[hubId] ?? const []);
  }

  @override
  Future<Deal> createDeal(DealDraft draft) async {
    final deal = Deal(
      id: 'mock-deal-${++_nextId}',
      hubId: draft.hubId,
      title: draft.title.trim(),
      description: draft.description,
      category: draft.category,
      totalPrice: draft.totalPrice,
      quantity: draft.quantity,
      // Nobody has claimed a share of a deal that was just published.
      availableSlots: draft.totalSlots,
      totalSlots: draft.totalSlots,
      pickupLocation: draft.pickupLocation.trim(),
      status: DealStatus.open,
      closesAt: draft.closesAt,
    );

    _dealsByHub.putIfAbsent(draft.hubId, () => []).insert(0, deal);
    return deal;
  }
}

abstract class SupabaseDealGateway {
  Future<List<Map<String, dynamic>>> getDeals(String hubId);

  Future<Map<String, dynamic>> insertDeal(Map<String, dynamic> values);
}

class PostgrestSupabaseDealGateway implements SupabaseDealGateway {
  PostgrestSupabaseDealGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> getDeals(String hubId) async {
    final rows = await _client
        .from('deals')
        .select()
        .eq('hub_id', hubId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, dynamic>> insertDeal(Map<String, dynamic> values) async {
    final row = await _client.from('deals').insert(values).select().single();
    return Map<String, dynamic>.from(row);
  }
}

class SupabaseDealRepository implements DealRepository {
  SupabaseDealRepository({
    required SupabaseDealGateway gateway,
    required String Function() currentUserId,
  }) : _gateway = gateway,
       _currentUserId = currentUserId;

  final SupabaseDealGateway _gateway;

  /// The insert policy checks `auth.uid() = created_by`, so a deal cannot be
  /// published without the signed-in student's id.
  final String Function() _currentUserId;

  @override
  Future<List<Deal>> getDeals(String hubId) async {
    final rows = await _gateway.getDeals(hubId);
    return rows.map(_mapDeal).toList();
  }

  @override
  Future<Deal> createDeal(DealDraft draft) async {
    try {
      final row = await _gateway.insertDeal({
        'hub_id': draft.hubId,
        'created_by': _currentUserId(),
        'title': draft.title.trim(),
        'description': draft.description?.trim(),
        'category': draft.category.name,
        'total_price': draft.totalPrice,
        'quantity': draft.quantity,
        'total_slots': draft.totalSlots,
        'available_slots': draft.totalSlots,
        'pickup_location': draft.pickupLocation.trim(),
        'status': _statusValue(DealStatus.open),
        'closes_at': draft.closesAt?.toIso8601String(),
      });
      return _mapDeal(row);
    } on PostgrestException catch (error) {
      throw DealFailure(_messageFor(error));
    }
  }

  String _messageFor(PostgrestException error) {
    // 42501 = insufficient_privilege, i.e. the insert policy rejected us.
    if (error.code == '42501') {
      return 'You do not have permission to post a deal in this hub.';
    }
    // 23503 = foreign_key_violation: the hub was deleted out from under us.
    if (error.code == '23503') {
      return 'That hub no longer exists.';
    }
    // 23514 = check_violation: the price/quantity/slot guards in the schema.
    if (error.code == '23514') {
      return 'Check the price, quantity and slots, then try again.';
    }
    return 'Could not publish the deal. Please try again.';
  }

  Deal _mapDeal(Map<String, dynamic> row) {
    final closesAt = row['closes_at'] as String?;

    return Deal(
      id: row['id'] as String,
      hubId: row['hub_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      category: _mapCategory(row['category'] as String),
      totalPrice: (row['total_price'] as num).toDouble(),
      quantity: (row['quantity'] as num).toInt(),
      availableSlots: (row['available_slots'] as num).toInt(),
      totalSlots: (row['total_slots'] as num).toInt(),
      pickupLocation: row['pickup_location'] as String,
      status: _mapStatus(row['status'] as String),
      closesAt: closesAt == null ? null : DateTime.parse(closesAt).toLocal(),
    );
  }

  DealCategory _mapCategory(String value) {
    return DealCategory.values.firstWhere(
      (category) => category.name == value,
      orElse: () => throw StateError('Unknown deal category "$value".'),
    );
  }

  DealStatus _mapStatus(String value) {
    return switch (value) {
      'open' => DealStatus.open,
      'filling_fast' => DealStatus.fillingFast,
      'full' => DealStatus.full,
      _ => throw StateError('Unknown deal status "$value".'),
    };
  }

  String _statusValue(DealStatus status) {
    return switch (status) {
      DealStatus.open => 'open',
      DealStatus.fillingFast => 'filling_fast',
      DealStatus.full => 'full',
    };
  }
}
