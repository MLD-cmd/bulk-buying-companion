import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseReservationRepository', () {
    test('reserving returns the deal with one fewer slot open', () async {
      final repository = SupabaseReservationRepository(
        gateway: _StubGateway(dealRow: _dealRow(availableSlots: 3)),
      );

      final deal = await repository.reserveSlot('deal-1');

      expect(deal.availableSlots, 3);
      expect(deal.totalSlots, 5);
    });

    test('says the deal filled up rather than a raw database error', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(
          const PostgrestException(message: 'Deal is full.', code: 'P0001'),
        ),
      );

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'This deal just filled up.',
          ),
        ),
      );
    });

    test('says the student already holds a slot', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(
          const PostgrestException(message: 'duplicate key', code: '23505'),
        ),
      );

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'You already have a slot in this deal.',
          ),
        ),
      );
    });

    test('says the deadline has passed', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(
          const PostgrestException(message: 'Deadline passed.', code: 'P0004'),
        ),
      );

      expect(
        () => repository.cancelReservation('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'The deadline has passed, so slots are locked.',
          ),
        ),
      );
    });

    test('says the host cannot walk away from their own buy', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(
          const PostgrestException(
            message: 'Host cannot cancel.',
            code: 'P0003',
          ),
        ),
      );

      expect(
        () => repository.cancelReservation('deal-1'),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'You are organising this buy, so your slot cannot be cancelled.',
          ),
        ),
      );
    });

    test('says the host slot is always paid', () async {
      final repository = SupabaseReservationRepository(
        gateway: _FailingGateway(
          const PostgrestException(
            message: 'Host slot is always paid.',
            code: 'P0013',
          ),
        ),
      );

      expect(
        () => repository.setPaid('deal-1', 'user-1', paid: false),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'The host slot is always paid.',
          ),
        ),
      );
    });

    test('lists the participants with the organiser first', () async {
      final repository = SupabaseReservationRepository(
        gateway: _StubGateway(
          dealRow: _dealRow(availableSlots: 3),
          participantRows: [
            {
              'deal_id': 'deal-1',
              'user_id': 'user-2',
              'reserved_at': '2026-07-14T02:00:00Z',
              'student_name': 'Bea Alonzo',
              'is_host': false,
            },
            {
              'deal_id': 'deal-1',
              'user_id': 'user-1',
              'reserved_at': '2026-07-14T01:00:00Z',
              'student_name': 'Marco Villanueva',
              'is_host': true,
            },
          ],
        ),
      );

      final participants = await repository.getParticipants('deal-1');

      expect(participants.map((p) => p.displayName), [
        'Marco Villanueva',
        'Bea Alonzo',
      ]);
      expect(participants.first.isHost, isTrue);
    });
  });

  group('MockReservationRepository', () {
    test('refuses a second slot for the same student', () async {
      final repository = MockReservationRepository(
        deal: _deal(availableSlots: 3),
        currentUserId: 'user-2',
      );

      await repository.reserveSlot('deal-1');

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('refuses a slot in a full deal', () async {
      final repository = MockReservationRepository(
        deal: _deal(availableSlots: 0),
        currentUserId: 'user-2',
      );

      expect(
        () => repository.reserveSlot('deal-1'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('refuses to cancel the host out of their own buy', () async {
      final repository = MockReservationRepository(
        deal: _deal(availableSlots: 3),
        currentUserId: 'user-1', // the host
      );

      expect(
        () => repository.cancelReservation('deal-1'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('has the host in the deal from the start', () async {
      final repository = MockReservationRepository(
        deal: _deal(availableSlots: 4),
        currentUserId: 'user-2',
      );

      final participants = await repository.getParticipants('deal-1');

      expect(participants.single.userId, 'user-1');
      expect(participants.single.isHost, isTrue);
    });
  });

  group('the host marks the deal along', () {
    late MockReservationRepository repository;

    Deal hostedDeal() => Deal(
      id: 'd',
      hubId: 'h',
      createdBy: 'host',
      title: 'Rice',
      category: DealCategory.grocery,
      totalPrice: 400,
      amount: 20,
      unit: DealUnit.kg,
      availableSlots: 3,
      totalSlots: 4,
      pickupLocation: 'Lobby',
      paidCount: 1,
    );

    setUp(() {
      repository = MockReservationRepository(
        deal: hostedDeal(),
        currentUserId: 'host',
      );
    });

    test(
      'marking every student paid makes a full deal ready to purchase',
      () async {
        await repository.reserveSlotFor('ana');
        await repository.reserveSlotFor('bea');
        await repository.reserveSlotFor('cy');
        expect(repository.deal.status, DealStatus.full);

        await repository.setPaid('d', 'ana', paid: true);
        await repository.setPaid('d', 'bea', paid: true);
        final deal = await repository.setPaid('d', 'cy', paid: true);

        expect(deal.status, DealStatus.readyToPurchase);
      },
    );

    test(
      'unmarking a payment takes it back out of ready to purchase',
      () async {
        await repository.reserveSlotFor('ana');
        await repository.reserveSlotFor('bea');
        await repository.reserveSlotFor('cy');
        await repository.setPaid('d', 'ana', paid: true);
        await repository.setPaid('d', 'bea', paid: true);
        await repository.setPaid('d', 'cy', paid: true);

        final deal = await repository.setPaid('d', 'cy', paid: false);
        expect(deal.status, DealStatus.full);
      },
    );

    test(
      'buying makes it ready for pickup and collects the host share',
      () async {
        // A student who has yet to collect keeps the deal at Ready for pickup;
        // buying auto-collects only the host's own share, not theirs.
        await repository.reserveSlotFor('ana');
        final deal = await repository.markPurchased('d');

        expect(deal.status, DealStatus.readyForPickup);
        final participants = await repository.getParticipants('d');
        final host = participants.firstWhere((p) => p.isHost);
        expect(host.hasCollected, isTrue);
      },
    );

    test('goods cannot be collected before they are bought', () async {
      await repository.reserveSlotFor('ana');

      expect(
        () => repository.setCollected('d', 'ana', collected: true),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('the last collection completes the deal', () async {
      await repository.reserveSlotFor('ana');
      await repository.markPurchased('d');

      final deal = await repository.setCollected('d', 'ana', collected: true);
      expect(deal.status, DealStatus.completed);
    });

    test('cancelling ends the deal', () async {
      final deal = await repository.cancelDeal('d');
      expect(deal.status, DealStatus.cancelled);
    });

    test('a completed deal cannot be cancelled', () async {
      await repository.reserveSlotFor('ana');
      await repository.markPurchased('d');
      await repository.setCollected('d', 'ana', collected: true);

      expect(
        () => repository.cancelDeal('d'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test('a student who has paid cannot walk away', () async {
      await repository.reserveSlotFor('ana');
      await repository.setPaid('d', 'ana', paid: true);

      expect(
        () => repository.cancelReservationFor('ana'),
        throwsA(isA<ReservationFailure>()),
      );
    });

    test(
      'the paid student is blocked through the real cancelReservation',
      () async {
        // Drives the production entry point rather than the seam, so the
        // paid-check is pinned where it sits among the host and closed checks.
        final ana = MockReservationRepository(
          deal: hostedDeal(),
          currentUserId: 'ana',
        );
        await ana.reserveSlot('d');
        await ana.markPaidForTest('ana');

        expect(
          () => ana.cancelReservation('d'),
          throwsA(
            isA<ReservationFailure>().having(
              (failure) => failure.message,
              'message',
              'You have already paid for this slot. Ask the host before you pull out.',
            ),
          ),
        );
      },
    );

    test('a student who is not the host cannot mark anyone paid', () async {
      final ana = MockReservationRepository(
        deal: hostedDeal(),
        currentUserId: 'ana',
      );

      expect(
        () => ana.setPaid('d', 'ana', paid: true),
        throwsA(isA<ReservationFailure>()),
      );
      expect(() => ana.markPurchased('d'), throwsA(isA<ReservationFailure>()));
      expect(() => ana.cancelDeal('d'), throwsA(isA<ReservationFailure>()));
    });

    test('the host cannot unpay themselves', () async {
      expect(
        () => repository.setPaid('d', 'host', paid: false),
        throwsA(
          isA<ReservationFailure>().having(
            (failure) => failure.message,
            'message',
            'The host slot is always paid.',
          ),
        ),
      );
      expect(repository.deal.paidCount, 1);
    });
  });
}

Map<String, dynamic> _dealRow({required int availableSlots}) => {
  'id': 'deal-1',
  'hub_id': 'colon',
  'title': '25kg Rice Sack',
  'description': null,
  'created_by': 'user-1',
  'category': 'grocery',
  'total_price': 900,
  'amount': 25,
  'unit': 'kg',
  'available_slots': availableSlots,
  'total_slots': 5,
  'pickup_location': 'USJR Main Gate',
  'status': 'open',
  'closes_at': null,
};

Deal _deal({required int availableSlots}) => Deal(
  id: 'deal-1',
  hubId: 'colon',
  title: '25kg Rice Sack',
  createdBy: 'user-1',
  category: DealCategory.grocery,
  totalPrice: 900,
  amount: 25,
  unit: DealUnit.kg,
  availableSlots: availableSlots,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);

class _StubGateway implements SupabaseReservationGateway {
  _StubGateway({required this.dealRow, this.participantRows = const []});

  final Map<String, dynamic> dealRow;
  final List<Map<String, dynamic>> participantRows;

  @override
  Future<Map<String, dynamic>> reserveSlot(String dealId) async => dealRow;

  @override
  Future<Map<String, dynamic>> cancelReservation(String dealId) async =>
      dealRow;

  @override
  Future<Map<String, dynamic>> setParticipantPaid(
    String dealId,
    String userId,
    bool paid,
  ) async => dealRow;

  @override
  Future<Map<String, dynamic>> setParticipantCollected(
    String dealId,
    String userId,
    bool collected,
  ) async => dealRow;

  @override
  Future<Map<String, dynamic>> markPurchased(String dealId) async => dealRow;

  @override
  Future<Map<String, dynamic>> cancelDeal(String dealId) async => dealRow;

  @override
  Future<List<Map<String, dynamic>>> getParticipants(String dealId) async =>
      participantRows;
}

class _FailingGateway implements SupabaseReservationGateway {
  _FailingGateway(this.error);

  final PostgrestException error;

  @override
  Future<Map<String, dynamic>> reserveSlot(String dealId) async => throw error;

  @override
  Future<Map<String, dynamic>> cancelReservation(String dealId) async =>
      throw error;

  @override
  Future<Map<String, dynamic>> setParticipantPaid(
    String dealId,
    String userId,
    bool paid,
  ) async => throw error;

  @override
  Future<Map<String, dynamic>> setParticipantCollected(
    String dealId,
    String userId,
    bool collected,
  ) async => throw error;

  @override
  Future<Map<String, dynamic>> markPurchased(String dealId) async =>
      throw error;

  @override
  Future<Map<String, dynamic>> cancelDeal(String dealId) async => throw error;

  @override
  Future<List<Map<String, dynamic>>> getParticipants(String dealId) async =>
      throw error;
}
