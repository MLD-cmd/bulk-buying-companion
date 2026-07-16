import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reliable participant state', () {
    test('starts loading and gates student reservation actions', () {
      final repository = _ControllableReservationRepository(
        deal: hostedDeal(availableSlots: 3, totalSlots: 4),
        currentUserId: 'ana',
      );
      final viewModel = _controlledViewModel(repository, userId: 'ana');

      expect(viewModel.isLoadingParticipants, isTrue);
      expect(viewModel.hasReliableParticipantState, isFalse);
      expect(viewModel.canReserve, isFalse);
      expect(viewModel.canCancel, isFalse);
    });

    test(
      'participant load failure is actionable and never confirmed empty',
      () async {
        final repository = _ControllableReservationRepository(
          deal: hostedDeal(availableSlots: 3, totalSlots: 4),
          currentUserId: 'ana',
        );
        final viewModel = _controlledViewModel(repository, userId: 'ana');

        repository.participantRequests.single.completeError(
          StateError('offline'),
        );
        await pumpEventQueue();

        expect(viewModel.isLoadingParticipants, isFalse);
        expect(viewModel.hasReliableParticipantState, isFalse);
        expect(
          viewModel.participantErrorMessage,
          'Couldn’t load who is in this deal. Try again before reserving a slot.',
        );
        expect(viewModel.participants, isEmpty);
        expect(viewModel.canReserve, isFalse);
        expect(viewModel.canCancel, isFalse);
      },
    );

    test(
      'a successful empty response alone enables an eligible student',
      () async {
        final repository = _ControllableReservationRepository(
          deal: hostedDeal(availableSlots: 3, totalSlots: 4),
          currentUserId: 'ana',
        );
        final viewModel = _controlledViewModel(repository, userId: 'ana');

        repository.participantRequests.single.complete(const []);
        await pumpEventQueue();

        expect(viewModel.hasReliableParticipantState, isTrue);
        expect(viewModel.participantErrorMessage, isNull);
        expect(viewModel.participants, isEmpty);
        expect(viewModel.canReserve, isTrue);
        expect(viewModel.canCancel, isFalse);
      },
    );

    test(
      'loaded participants restore holds, cancel, and reserve rules',
      () async {
        final repository = _ControllableReservationRepository(
          deal: hostedDeal(availableSlots: 3, totalSlots: 4),
          currentUserId: 'ana',
        );
        final viewModel = _controlledViewModel(repository, userId: 'ana');

        repository.participantRequests.single.complete([_reservation('ana')]);
        await pumpEventQueue();

        expect(viewModel.holdsSlot, isTrue);
        expect(viewModel.canCancel, isTrue);
        expect(viewModel.canReserve, isFalse);
      },
    );

    test(
      'retry clears the error, reloads, and restores real eligibility',
      () async {
        final repository = _ControllableReservationRepository(
          deal: hostedDeal(availableSlots: 3, totalSlots: 4),
          currentUserId: 'ana',
        );
        final viewModel = _controlledViewModel(repository, userId: 'ana');
        repository.participantRequests.single.completeError(
          StateError('offline'),
        );
        await pumpEventQueue();

        final retry = viewModel.retryParticipants();

        expect(viewModel.isLoadingParticipants, isTrue);
        expect(viewModel.participantErrorMessage, isNull);
        expect(viewModel.hasReliableParticipantState, isFalse);
        expect(repository.participantRequests, hasLength(2));

        repository.participantRequests.last.complete([_reservation('ana')]);
        await retry;

        expect(viewModel.isLoadingParticipants, isFalse);
        expect(viewModel.participantErrorMessage, isNull);
        expect(viewModel.holdsSlot, isTrue);
        expect(viewModel.canCancel, isTrue);

        final failedRetry = viewModel.retryParticipants();
        repository.participantRequests.last.completeError(
          StateError('offline again'),
        );
        await failedRetry;
        expect(
          viewModel.participantErrorMessage,
          'Couldn’t load who is in this deal. Try again before reserving a slot.',
        );
      },
    );

    test('failed retry keeps cache but makes it ineligible', () async {
      final repository = _ControllableReservationRepository(
        deal: hostedDeal(availableSlots: 3, totalSlots: 4),
        currentUserId: 'ana',
      );
      final viewModel = _controlledViewModel(repository, userId: 'ana');
      repository.participantRequests.single.complete([_reservation('ana')]);
      await pumpEventQueue();

      final retry = viewModel.retryParticipants();
      repository.participantRequests.last.completeError(StateError('offline'));
      await retry;

      expect(viewModel.participants, hasLength(1));
      expect(viewModel.holdsSlot, isTrue, reason: 'the cache is retained');
      expect(viewModel.hasReliableParticipantState, isFalse);
      expect(viewModel.canCancel, isFalse);
      expect(viewModel.canReserve, isFalse);
    });

    test('mutation success survives a participant refresh failure', () async {
      final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
      final repository = _ControllableReservationRepository(
        deal: deal,
        currentUserId: 'ana',
      );
      final viewModel = _controlledViewModel(repository, userId: 'ana');
      repository.participantRequests.single.complete(const []);
      await pumpEventQueue();

      final mutation = viewModel.reserve();
      repository.reserveRequest.complete(deal.copyWith(availableSlots: 2));
      await pumpEventQueue();
      repository.participantRequests.last.completeError(
        StateError('refresh offline'),
      );
      await mutation;

      expect(viewModel.deal.availableSlots, 2);
      expect(viewModel.errorMessage, isNull);
      expect(
        viewModel.participantErrorMessage,
        'Couldn’t load who is in this deal. Try again before reserving a slot.',
      );
      expect(viewModel.canReserve, isFalse);

      final retry = viewModel.retryParticipants();
      repository.participantRequests.last.complete([_reservation('ana')]);
      await retry;
      expect(viewModel.holdsSlot, isTrue);
      expect(viewModel.canCancel, isTrue);
    });

    test(
      'mutation failure preserves deal and participants independently',
      () async {
        final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
        final repository = _ControllableReservationRepository(
          deal: deal,
          currentUserId: 'ana',
        );
        final viewModel = _controlledViewModel(repository, userId: 'ana');
        repository.participantRequests.single.complete(const []);
        await pumpEventQueue();

        final mutation = viewModel.reserve();
        repository.reserveRequest.completeError(
          const ReservationFailure('This deal just filled up.'),
        );
        await mutation;

        expect(viewModel.deal, same(deal));
        expect(viewModel.participants, isEmpty);
        expect(viewModel.errorMessage, 'This deal just filled up.');
        expect(viewModel.participantErrorMessage, isNull);
        expect(repository.participantRequests, hasLength(1));
      },
    );

    test(
      'stale participant and deal completions cannot overwrite newer state',
      () async {
        final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
        final repository = _ControllableReservationRepository(
          deal: deal,
          currentUserId: 'ana',
        );
        final viewModel = _controlledViewModel(repository, userId: 'ana');

        final retry = viewModel.retryParticipants();
        repository.participantRequests.last.complete([_reservation('ana')]);
        await retry;
        repository.participantRequests.first.complete([_reservation('bea')]);
        await pumpEventQueue();
        expect(viewModel.participants.single.userId, 'ana');

        final mutation = viewModel.reserve();
        final externallyRefreshed = deal.copyWith(availableSlots: 1);
        viewModel.refreshDeal(externallyRefreshed);
        repository.reserveRequest.complete(deal.copyWith(availableSlots: 2));
        await mutation;

        expect(viewModel.deal, same(externallyRefreshed));
        expect(repository.participantRequests, hasLength(2));
      },
    );

    test(
      'double mutation is exact once while its request is unresolved',
      () async {
        final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
        final repository = _ControllableReservationRepository(
          deal: deal,
          currentUserId: 'ana',
        );
        final viewModel = _controlledViewModel(repository, userId: 'ana');
        repository.participantRequests.single.complete(const []);
        await pumpEventQueue();

        final first = viewModel.reserve();
        final second = viewModel.reserve();
        expect(repository.reserveCalls, 1);

        repository.reserveRequest.complete(deal.copyWith(availableSlots: 2));
        await pumpEventQueue();
        repository.participantRequests.last.complete([_reservation('ana')]);
        await Future.wait([first, second]);

        expect(repository.reserveCalls, 1);
        expect(viewModel.deal.availableSlots, 2);
      },
    );

    test(
      'dispose invalidates initial and retry participant completions',
      () async {
        final repository = _ControllableReservationRepository(
          deal: hostedDeal(availableSlots: 3, totalSlots: 4),
          currentUserId: 'ana',
        );
        final initialViewModel = _controlledViewModel(
          repository,
          userId: 'ana',
        );
        var notifications = 0;
        initialViewModel.addListener(() => notifications++);
        initialViewModel.dispose();
        repository.participantRequests.single.complete([_reservation('ana')]);
        await pumpEventQueue();
        expect(notifications, 0);
        expect(initialViewModel.participants, isEmpty);

        final retryRepository = _ControllableReservationRepository(
          deal: hostedDeal(availableSlots: 3, totalSlots: 4),
          currentUserId: 'ana',
        );
        final retryViewModel = _controlledViewModel(
          retryRepository,
          userId: 'ana',
        );
        retryRepository.participantRequests.single.complete(const []);
        await pumpEventQueue();
        final retry = retryViewModel.retryParticipants();
        retryViewModel.dispose();
        retryRepository.participantRequests.last.complete([
          _reservation('ana'),
        ]);
        await retry;
        expect(retryViewModel.participants, isEmpty);
      },
    );

    test('dispose invalidates mutations and their follow-up refresh', () async {
      final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
      final mutationRepository = _ControllableReservationRepository(
        deal: deal,
        currentUserId: 'ana',
      );
      final mutationViewModel = _controlledViewModel(
        mutationRepository,
        userId: 'ana',
      );
      mutationRepository.participantRequests.single.complete(const []);
      await pumpEventQueue();
      final mutation = mutationViewModel.reserve();
      mutationViewModel.dispose();
      mutationRepository.reserveRequest.complete(
        deal.copyWith(availableSlots: 2),
      );
      await mutation;
      expect(mutationViewModel.deal, same(deal));

      final refreshRepository = _ControllableReservationRepository(
        deal: deal,
        currentUserId: 'ana',
      );
      final refreshViewModel = _controlledViewModel(
        refreshRepository,
        userId: 'ana',
      );
      refreshRepository.participantRequests.single.complete(const []);
      await pumpEventQueue();
      final refresh = refreshViewModel.reserve();
      refreshRepository.reserveRequest.complete(
        deal.copyWith(availableSlots: 2),
      );
      await pumpEventQueue();
      expect(refreshRepository.participantRequests, hasLength(2));
      refreshViewModel.dispose();
      refreshRepository.participantRequests.last.complete([
        _reservation('ana'),
      ]);
      await refresh;
      expect(refreshViewModel.participants, isEmpty);
    });
  });

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
}

DealDetailsViewModel _controlledViewModel(
  _ControllableReservationRepository repository, {
  required String userId,
}) {
  return DealDetailsViewModel(
    reservationRepository: repository,
    deal: repository.deal,
    currentUserId: userId,
  );
}

Reservation _reservation(String userId, {bool paid = false}) {
  return Reservation(
    dealId: 'd',
    userId: userId,
    studentName: userId == 'ana' ? 'Ana' : 'Bea',
    reservedAt: DateTime(2026, 7, 14),
    paidAt: paid ? DateTime(2026, 7, 15) : null,
  );
}

class _ControllableReservationRepository implements ReservationRepository {
  _ControllableReservationRepository({
    required Deal deal,
    required String currentUserId,
  }) : _delegate = MockReservationRepository(
         deal: deal,
         currentUserId: currentUserId,
       );

  final MockReservationRepository _delegate;
  final List<Completer<List<Reservation>>> participantRequests = [];
  final Completer<Deal> reserveRequest = Completer<Deal>();
  int reserveCalls = 0;

  Deal get deal => _delegate.deal;

  @override
  Future<List<Reservation>> getParticipants(String dealId) {
    final request = Completer<List<Reservation>>();
    participantRequests.add(request);
    return request.future;
  }

  @override
  Future<Deal> reserveSlot(String dealId) {
    reserveCalls++;
    return reserveRequest.future;
  }

  @override
  Future<Deal> cancelReservation(String dealId) =>
      _delegate.cancelReservation(dealId);

  @override
  Future<Deal> setPaid(String dealId, String userId, {required bool paid}) =>
      _delegate.setPaid(dealId, userId, paid: paid);

  @override
  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  }) => _delegate.setCollected(dealId, userId, collected: collected);

  @override
  Future<Deal> markPurchased(String dealId) => _delegate.markPurchased(dealId);

  @override
  Future<Deal> cancelDeal(String dealId) => _delegate.cancelDeal(dealId);
}

Deal hostedDeal({required int availableSlots, required int totalSlots}) {
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
    paidCount: 1,
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
