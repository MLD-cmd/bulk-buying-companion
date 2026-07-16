import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reserving takes a slot and puts the student in the list', () async {
    final viewModel = _viewModel(userId: 'user-2');
    await pumpEventQueue();

    expect(viewModel.holdsSlot, isFalse);
    expect(viewModel.deal.availableSlots, 4);

    await viewModel.reserve();

    expect(viewModel.holdsSlot, isTrue);
    expect(viewModel.deal.availableSlots, 3);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.isUpdating, isFalse);
  });

  test('cancelling gives the slot back', () async {
    final viewModel = _viewModel(userId: 'user-2');
    await pumpEventQueue();

    await viewModel.reserve();
    await viewModel.cancel();

    expect(viewModel.holdsSlot, isFalse);
    expect(viewModel.deal.availableSlots, 4);
  });

  test('a double-tapped reserve claims one slot, not two', () async {
    final viewModel = _viewModel(userId: 'user-2');
    await pumpEventQueue();

    // Both taps land before the first call resolves.
    final first = viewModel.reserve();
    final second = viewModel.reserve();
    await Future.wait([first, second]);

    expect(viewModel.deal.availableSlots, 3, reason: 'one slot, not two');
    expect(viewModel.errorMessage, isNull, reason: 'the second tap is a no-op');
  });

  test('the host holds a slot and cannot give it up', () async {
    final viewModel = _viewModel(userId: 'user-1'); // the host
    await pumpEventQueue();

    expect(viewModel.isHost, isTrue);
    expect(viewModel.holdsSlot, isTrue);
    expect(viewModel.canCancel, isFalse);

    await viewModel.cancel();

    expect(
      viewModel.errorMessage,
      'You are organising this buy, so your slot cannot be cancelled.',
    );
    expect(viewModel.deal.availableSlots, 4, reason: 'nothing was released');
  });

  test('surfaces a full deal as a message, not a crash', () async {
    final viewModel = _viewModel(userId: 'user-2', availableSlots: 0);
    await pumpEventQueue();

    expect(viewModel.isFull, isTrue);

    await viewModel.reserve();

    expect(viewModel.errorMessage, 'This deal just filled up.');
    expect(viewModel.holdsSlot, isFalse);
  });

  test('the host is told what is still to collect', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.reserveSlotFor('bea');
    await repository.reserveSlotFor('cy');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    // Only the host's own slot is paid, and that is not money they hold.
    expect(viewModel.paymentLabel, '1 of 4 paid — P300 still to collect');

    await viewModel.setPaid('ana', paid: true);
    expect(viewModel.paymentLabel, '2 of 4 paid — P200 still to collect');
  });

  test('the host can buy once the deal is full, and not before', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'host',
    );
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    expect(viewModel.canMarkPurchased, isFalse);

    await repository.reserveSlotFor('ana');
    viewModel.refreshDeal(repository.deal);
    expect(viewModel.canMarkPurchased, isTrue);

    await viewModel.markPurchased();
    expect(viewModel.deal.status, DealStatus.readyForPickup);
    expect(viewModel.canMarkPurchased, isFalse);
    expect(viewModel.canMarkCollected, isTrue);
    expect(
      viewModel.pickupProgressLabel,
      '1 of 2 picked up - 1 pickup remaining',
    );
  });

  test('pickup progress completes when the last student collects', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.markPurchased('d');
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    expect(
      viewModel.pickupProgressLabel,
      '1 of 2 picked up - 1 pickup remaining',
    );

    await viewModel.setCollected('ana', collected: true);

    expect(viewModel.deal.status, DealStatus.completed);
    expect(viewModel.pickupProgressLabel, 'All 2 pickups are collected.');
  });

  test('a student sees no host controls', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'ana',
    );
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'ana',
    );
    await pumpEventQueue();

    expect(viewModel.isHost, isFalse);
    expect(viewModel.canMarkPurchased, isFalse);
    expect(viewModel.canCancelDeal, isFalse);
    expect(viewModel.canMarkPaid, isFalse);
  });

  test('cancelling names the money the host is holding', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.reserveSlotFor('bea');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    await viewModel.setPaid('ana', paid: true);
    await viewModel.setPaid('bea', paid: true);

    expect(viewModel.canCancelDeal, isTrue);
    expect(viewModel.refundWarning, '2 students have paid you P200.');

    await viewModel.cancelDeal();
    expect(viewModel.deal.status, DealStatus.cancelled);
    expect(viewModel.canCancelDeal, isFalse);
    expect(viewModel.canReserve, isFalse);
  });

  test('one paid student is warned about in the singular', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    await viewModel.setPaid('ana', paid: true);
    expect(viewModel.refundWarning, '1 student has paid you P100.');
  });

  test('a refused host action surfaces as a message, not a crash', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    // Nobody has collected goods that were never bought.
    await viewModel.setCollected('ana', collected: true);

    expect(viewModel.errorMessage, 'The goods have not been bought yet.');
    expect(viewModel.isUpdating, isFalse);
  });

  test('nobody has paid, so there is nothing to warn about', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    expect(viewModel.refundWarning, isNull);
  });

  test('a paid student cannot cancel their slot', () async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    await repository.reserveSlotFor('ana');
    await repository.markPaidForTest('ana');

    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.deal,
      currentUserId: 'ana',
    );
    await pumpEventQueue();

    expect(viewModel.holdsSlot, isTrue);
    expect(viewModel.canCancel, isFalse);
  });

  test('updates when another student changes the open deal', () async {
    final repository = _LiveReservationRepository(
      snapshot: DealDetailsSnapshot(
        deal: hostedDeal(availableSlots: 1, totalSlots: 2),
        participants: [
          _participant(
            'd',
            'host',
            isHost: true,
            paidAt: DateTime(2026, 7, 16),
          ),
        ],
      ),
    );
    final viewModel = DealDetailsViewModel(
      reservationRepository: repository,
      deal: repository.snapshot.deal,
      currentUserId: 'host',
    );
    await pumpEventQueue();

    expect(viewModel.canMarkPurchased, isFalse);

    repository.emit(
      DealDetailsSnapshot(
        deal: hostedDeal(availableSlots: 0, totalSlots: 2, paidCount: 2),
        participants: [
          _participant(
            'd',
            'host',
            isHost: true,
            paidAt: DateTime(2026, 7, 16),
          ),
          _participant('d', 'ana', paidAt: DateTime(2026, 7, 16)),
        ],
      ),
    );
    await pumpEventQueue();

    expect(viewModel.deal.availableSlots, 0);
    expect(viewModel.participants.map((participant) => participant.userId), [
      'host',
      'ana',
    ]);
    expect(viewModel.canMarkPurchased, isTrue);
  });
}

Deal hostedDeal({
  required int availableSlots,
  required int totalSlots,
  int paidCount = 1,
}) {
  return Deal(
    id: 'd',
    hubId: 'h',
    createdBy: 'host',
    title: 'Rice',
    category: DealCategory.grocery,
    totalPrice: 400,
    amount: 20,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: totalSlots,
    pickupLocation: 'Lobby',
    paidCount: paidCount,
  );
}

class _LiveReservationRepository
    implements ReservationRepository, RealtimeReservationRepository {
  _LiveReservationRepository({required this.snapshot});

  DealDetailsSnapshot snapshot;
  final _controller = StreamController<DealDetailsSnapshot>();

  void emit(DealDetailsSnapshot value) {
    snapshot = value;
    _controller.add(value);
  }

  @override
  Stream<DealDetailsSnapshot> watchDealDetails(Deal deal) async* {
    yield snapshot;
    yield* _controller.stream;
  }

  @override
  Future<List<Reservation>> getParticipants(String dealId) async =>
      snapshot.participants;

  @override
  Future<Deal> reserveSlot(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> cancelReservation(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> setPaid(String dealId, String userId, {required bool paid}) {
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
  Future<Deal> markPurchased(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> cancelDeal(String dealId) {
    throw UnimplementedError();
  }
}

Reservation _participant(
  String dealId,
  String userId, {
  bool isHost = false,
  DateTime? paidAt,
}) {
  return Reservation(
    dealId: dealId,
    userId: userId,
    isHost: isHost,
    reservedAt: DateTime(2026, 7, 16),
    paidAt: paidAt,
  );
}

DealDetailsViewModel _viewModel({
  required String userId,
  int availableSlots = 4,
}) {
  final deal = Deal(
    id: 'deal-1',
    hubId: 'colon',
    title: '25kg Rice Sack',
    createdBy: 'user-1',
    category: DealCategory.grocery,
    totalPrice: 900,
    amount: 1,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: 5,
    pickupLocation: 'USJR Main Gate',
  );

  return DealDetailsViewModel(
    deal: deal,
    currentUserId: userId,
    reservationRepository: MockReservationRepository(
      deal: deal,
      currentUserId: userId,
    ),
  );
}
