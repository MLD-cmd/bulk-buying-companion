import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps a deal row onto the model', () async {
    final repository = SupabaseDealRepository(
      gateway: _FakeSupabaseDealGateway(
        rows: [
          {
            'id': 'deal-1',
            'hub_id': 'colon',
            'title': '25kg Rice Sack',
            'description': 'Sinandomeng',
            'category': 'grocery',
            'total_price': 900,
            'amount': 25,
            'unit': 'kg',
            'available_slots': 3,
            'total_slots': 5,
            'pickup_location': 'USJR Main Gate',
            'status': 'open',
            'closes_at': '2026-07-16T15:59:00.000Z',
            'created_by': 'user-9',
            'host_name': 'Marco Villanueva',
          },
        ],
      ),
      currentUserId: () => 'user-1',
    );

    final deals = await repository.getDeals('colon');

    expect(deals, hasLength(1));
    expect(deals.single.title, '25kg Rice Sack');
    expect(deals.single.description, 'Sinandomeng');
    expect(deals.single.category, DealCategory.grocery);
    expect(deals.single.totalPrice, 900);
    expect(deals.single.status, DealStatus.open);
    expect(deals.single.priceLabel, 'P180/share');
    expect(deals.single.closesAt, isNotNull);
    // host_name only exists on the deal_feed view, not the deals table.
    expect(deals.single.createdBy, 'user-9');
    expect(deals.single.hostName, 'Marco Villanueva');
  });

  test('falls back when the deal_feed row has no host name', () async {
    final repository = SupabaseDealRepository(
      gateway: _FakeSupabaseDealGateway(
        rows: [
          {
            'id': 'deal-2',
            'hub_id': 'colon',
            'title': 'Cooking Oil 5L',
            'category': 'pantry',
            'total_price': 750,
            'amount': 5,
            'unit': 'litre',
            'available_slots': 5,
            'total_slots': 5,
            'pickup_location': 'USJR Main Gate',
            'status': 'open',
            'host_name': null,
          },
        ],
      ),
      currentUserId: () => 'user-1',
    );

    final deals = await repository.getDeals('colon');

    expect(deals.single.hostName, isNull);
    expect(deals.single.hostLabel, 'A student in this hub');
  });

  test('publishes a deal with the signed-in student as the author', () async {
    final gateway = _FakeSupabaseDealGateway();
    final repository = SupabaseDealRepository(
      gateway: gateway,
      currentUserId: () => 'user-1',
    );

    final deal = await repository.createDeal(
      const DealDraft(
        hubId: 'colon',
        title: 'Cooking Oil 5L',
        category: DealCategory.pantry,
        totalPrice: 750,
        amount: 5,
        unit: DealUnit.litre,
        totalSlots: 5,
        pickupLocation: 'USJR Main Gate',
      ),
    );

    // The insert policy checks auth.uid() = created_by, so the row has to
    // carry the current user's id or the database refuses it.
    expect(gateway.insertedValues!['created_by'], 'user-1');
    expect(gateway.insertedValues!['category'], 'pantry');
    expect(gateway.insertedValues!['amount'], 5);
    expect(gateway.insertedValues!['unit'], 'litre');
    expect(gateway.insertedValues!['status'], 'open');
    // available_slots is not sent -- the deals_set_available_slots trigger
    // owns that column, seating the host in one of the slots.
    expect(gateway.insertedValues!.containsKey('available_slots'), isFalse);
    expect(deal.availableSlots, 4);
    expect(deal.status, DealStatus.open);
  });

  test('reports a refused insert as a permission failure', () async {
    final repository = SupabaseDealRepository(
      gateway: _FakeSupabaseDealGateway(
        insertError: PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        ),
      ),
      currentUserId: () => 'user-1',
    );

    expect(
      () => repository.createDeal(_draft),
      throwsA(
        isA<DealFailure>().having(
          (failure) => failure.message,
          'message',
          'You do not have permission to post a deal in this hub.',
        ),
      ),
    );
  });

  test('reports a check violation against the price and slot guards', () async {
    final repository = SupabaseDealRepository(
      gateway: _FakeSupabaseDealGateway(
        insertError: PostgrestException(
          message: 'violates check constraint "deals_total_price_check"',
          code: '23514',
        ),
      ),
      currentUserId: () => 'user-1',
    );

    expect(
      () => repository.createDeal(_draft),
      throwsA(
        isA<DealFailure>().having(
          (failure) => failure.message,
          'message',
          'Check the price, amount and slots, then try again.',
        ),
      ),
    );
  });
}

const _draft = DealDraft(
  hubId: 'colon',
  title: 'Cooking Oil 5L',
  category: DealCategory.pantry,
  totalPrice: 750,
  amount: 5,
  unit: DealUnit.litre,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);

class _FakeSupabaseDealGateway implements SupabaseDealGateway {
  _FakeSupabaseDealGateway({
    List<Map<String, dynamic>> rows = const [],
    this.insertError,
  }) : _rows = List.of(rows);

  final List<Map<String, dynamic>> _rows;
  final PostgrestException? insertError;

  Map<String, dynamic>? insertedValues;

  @override
  Future<List<Map<String, dynamic>>> getDeals(String hubId) async {
    return _rows.where((row) => row['hub_id'] == hubId).toList();
  }

  @override
  Future<Map<String, dynamic>> insertDeal(Map<String, dynamic> values) async {
    final error = insertError;
    if (error != null) throw error;

    insertedValues = values;
    // Postgres fills in the id and created_at defaults on the way back, and
    // the deals_set_available_slots trigger seats the host in one of the
    // slots -- mirrored here so this fake matches the real database.
    final row = {
      ...values,
      'id': 'deal-generated',
      'available_slots': (values['total_slots'] as int) - 1,
    };
    _rows.add(row);
    return row;
  }
}
