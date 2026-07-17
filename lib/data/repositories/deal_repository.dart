import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/deal.dart';
import '../../models/deal_unit.dart';

/// Turns a `deals` (or `deal_feed`) row into a [Deal].
///
/// Top-level rather than private to the repository: the reservation RPCs also
/// return a deals row, and two copies of this mapping would be two things to
/// keep in step.
Deal dealFromRow(Map<String, dynamic> row) {
  final closesAt = row['closes_at'] as String?;
  final purchasedAt = row['purchased_at'] as String?;
  final cancelledAt = row['cancelled_at'] as String?;

  return Deal(
    id: row['id'] as String,
    hubId: row['hub_id'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    createdBy: row['created_by'] as String?,
    // Absent when the row came back from the deals table rather than the
    // deal_feed view, which is what carries it.
    hostName: row['host_name'] as String?,
    category: _dealCategoryFromValue(row['category'] as String),
    totalPrice: (row['total_price'] as num).toDouble(),
    amount: (row['amount'] as num).toDouble(),
    unit: _dealUnitFromValue(row['unit'] as String),
    availableSlots: (row['available_slots'] as num).toInt(),
    totalSlots: (row['total_slots'] as num).toInt(),
    pickupLocation: row['pickup_location'] as String,
    closesAt: closesAt == null ? null : DateTime.parse(closesAt).toLocal(),
    purchasedAt: purchasedAt == null
        ? null
        : DateTime.parse(purchasedAt).toLocal(),
    cancelledAt: cancelledAt == null
        ? null
        : DateTime.parse(cancelledAt).toLocal(),
    // Absent on the raw deals row an insert returns; deal_feed carries them.
    paidCount: (row['paid_count'] as num?)?.toInt() ?? 0,
    collectedCount: (row['collected_count'] as num?)?.toInt() ?? 0,
  );
}

DealCategory _dealCategoryFromValue(String value) {
  return DealCategory.values.firstWhere(
    (category) => category.name == value,
    orElse: () => throw StateError('Unknown deal category "$value".'),
  );
}

DealUnit _dealUnitFromValue(String value) {
  return DealUnit.values.firstWhere(
    (unit) => unit.name == value,
    orElse: () => throw StateError('Unknown deal unit "$value".'),
  );
}

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

/// Seed deadlines are offsets from now, not calendar dates: a fixed date turns
/// every seed expired a few days after it is written, which silently closes the
/// demo data the lifecycle statuses are meant to show.
DateTime _closesIn(int days) =>
    DateTime.now().add(Duration(days: days)).copyWith(hour: 23, minute: 59);

/// In-memory stand-in. Deals are stubbed per hub so the Split Board renders
/// with placeholder cards in tests.
class MockDealRepository implements DealRepository {
  /// Between them the seeds walk the lifecycle — Open, Filling fast, Full,
  /// Ready to purchase — so the statuses are visible when the app runs on mock
  /// data. Every one of them has a host, and a host's slot is paid from the
  /// moment the deal exists, so no seed can have participants and nobody paid.
  MockDealRepository()
    : _dealsByHub = {
        'colon': [
          Deal(
            id: 'colon-rice',
            createdBy: 'marco',
            hostName: 'Marco Villanueva',
            hubId: 'colon',
            title: '25kg Rice Sack — Split 5 ways',
            totalPrice: 900,
            amount: 25,
            unit: DealUnit.kg,
            category: DealCategory.grocery,
            availableSlots: 3,
            totalSlots: 5,
            pickupLocation: 'USJR Main Gate',
            paidCount: 1,
            closesAt: _closesIn(3),
          ),
          // Down to its last slot.
          Deal(
            id: 'colon-water',
            createdBy: 'bea',
            hostName: 'Bea Alonzo',
            hubId: 'colon',
            title: 'Bottled Water Case (24pk)',
            totalPrice: 380,
            amount: 24,
            unit: DealUnit.bottles,
            category: DealCategory.drinks,
            availableSlots: 1,
            totalSlots: 4,
            pickupLocation: 'Colon Street Hub',
            paidCount: 2,
            closesAt: _closesIn(1),
          ),
          Deal(
            id: 'colon-detergent',
            createdBy: 'rey',
            hostName: 'Rey Mercado',
            hubId: 'colon',
            title: 'Laundry Detergent 6L',
            totalPrice: 360,
            amount: 6,
            unit: DealUnit.litre,
            category: DealCategory.household,
            availableSlots: 0,
            totalSlots: 3,
            pickupLocation: 'Barangay Hall Lobby',
            // Full, and still waiting on one student's money.
            paidCount: 2,
            closesAt: _closesIn(5),
          ),
        ],
        'magallanes': [
          Deal(
            id: 'magallanes-eggs',
            createdBy: 'trina',
            hostName: 'Trina Lopez',
            hubId: 'magallanes',
            title: 'Egg Tray (30s) — Split 3 ways',
            totalPrice: 255,
            amount: 30,
            unit: DealUnit.pieces,
            category: DealCategory.grocery,
            availableSlots: 1,
            totalSlots: 3,
            pickupLocation: 'Magallanes Residence Gate',
            paidCount: 1,
            closesAt: _closesIn(2),
          ),
          // Full and everyone has paid, so it is waiting on Karl to go and buy
          // the coffee.
          Deal(
            id: 'magallanes-coffee',
            createdBy: 'karl',
            hostName: 'Karl Diaz',
            hubId: 'magallanes',
            title: '3-in-1 Coffee Bulk Pack',
            totalPrice: 900,
            amount: 60,
            unit: DealUnit.sachets,
            category: DealCategory.pantry,
            availableSlots: 0,
            totalSlots: 6,
            pickupLocation: 'Tower A Lobby',
            paidCount: 6,
            closesAt: _closesIn(6),
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
      amount: draft.amount,
      unit: draft.unit,
      // The host is one of the students splitting the buy: "split 5 ways" means
      // them and four others. Mirrors the deals_set_available_slots trigger.
      availableSlots: draft.totalSlots - 1,
      totalSlots: draft.totalSlots,
      pickupLocation: draft.pickupLocation.trim(),
      // A new deal has exactly one participant, the host, and the host's slot is
      // paid from the moment it exists — they cannot pay themselves.
      paidCount: 1,
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

  /// Reads the deal_feed view rather than the deals table: it carries the
  /// host's display name, which lives in profiles and is not readable there
  /// (that policy is own-row-only, by design — profiles also holds emails).
  @override
  Future<List<Map<String, dynamic>>> getDeals(String hubId) async {
    final rows = await _client
        .from('deal_feed')
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
    return rows.map(dealFromRow).toList();
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
        'amount': draft.amount,
        // Stored by Dart name, as category is: 'litre', not 'L'.
        'unit': draft.unit.name,
        'total_slots': draft.totalSlots,
        'pickup_location': draft.pickupLocation.trim(),
        'closes_at': draft.closesAt?.toIso8601String(),
      });
      // The insert returns the raw deals row, which carries no counts. The
      // trigger has just given the host their slot, and a host's slot is paid
      // from the moment it exists -- they cannot pay themselves.
      return dealFromRow(row).copyWith(paidCount: 1);
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
    // 23514 = check_violation: the price/amount/slot guards in the schema.
    if (error.code == '23514') {
      return 'Check the price, amount and slots, then try again.';
    }
    return 'Could not publish the deal. Please try again.';
  }
}
