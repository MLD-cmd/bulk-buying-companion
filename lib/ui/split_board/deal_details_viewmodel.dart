import 'package:flutter/foundation.dart';

import '../../data/repositories/reservation_repository.dart';
import '../../models/deal.dart';
import '../../models/reservation.dart';

/// Drives one deal's detail screen: who is in the buy, and whether this student
/// can take or give up a slot.
class DealDetailsViewModel extends ChangeNotifier {
  DealDetailsViewModel({
    required ReservationRepository reservationRepository,
    required Deal deal,
    required this.currentUserId,
  }) : _reservationRepository = reservationRepository,
       _deal = deal {
    _loadParticipants();
  }

  final ReservationRepository _reservationRepository;
  final String? currentUserId;

  Deal _deal;
  List<Reservation> _participants = const [];
  bool _isLoadingParticipants = true;
  String? _participantErrorMessage;
  int _participantGeneration = 0;
  bool _isUpdating = false;
  String? _errorMessage;
  int _mutationGeneration = 0;
  int _dealGeneration = 0;
  bool _isDisposed = false;

  Deal get deal => _deal;
  List<Reservation> get participants => _participants;
  bool get isLoadingParticipants => _isLoadingParticipants;
  String? get participantErrorMessage => _participantErrorMessage;
  bool get hasReliableParticipantState =>
      !_isLoadingParticipants && _participantErrorMessage == null;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;

  bool get isFull => _deal.availableSlots == 0;
  bool get isHost => currentUserId != null && _deal.createdBy == currentUserId;

  bool get holdsSlot =>
      _participants.any((participant) => participant.userId == currentUserId);

  bool get deadlinePassed {
    final closesAt = _deal.closesAt;
    return closesAt != null && !closesAt.isAfter(DateTime.now());
  }

  bool get isCancelled => _deal.status == DealStatus.cancelled;
  bool get isCompleted => _deal.status == DealStatus.completed;
  bool get isPurchased => _deal.purchasedAt != null;

  /// Once the host has bought or called it off, the count they spent money
  /// against is final: nobody joins and nobody leaves.
  bool get isClosed => isPurchased || isCancelled;

  bool get currentUserHasPaid => _participants.any(
    (participant) => participant.userId == currentUserId && participant.hasPaid,
  );

  /// The host is the person everyone else is relying on, so they cannot walk
  /// away from their own buy; past the deadline the host is about to spend real
  /// money against a count that must now be final; and a student who has paid
  /// would be leaving the host holding money they owe back.
  bool get canCancel =>
      hasReliableParticipantState &&
      holdsSlot &&
      !isHost &&
      !deadlinePassed &&
      !isClosed &&
      !currentUserHasPaid;

  bool get canReserve =>
      hasReliableParticipantState &&
      !holdsSlot &&
      !isFull &&
      !deadlinePassed &&
      !isClosed;

  /// The host's levers. The screen offers "I've bought it" from Full onward —
  /// the normal path — though the database does not insist on it.
  bool get canMarkPurchased => isHost && isFull && !isPurchased && !isCancelled;
  bool get canCancelDeal => isHost && !isCompleted && !isCancelled;

  /// A payment can be recorded at any point until the deal is cancelled -- a
  /// student who settles up late, after pickup, still gets ticked off.
  bool get canMarkPaid => isHost && !isCancelled;
  bool get canMarkCollected => isHost && isPurchased && !isCancelled;

  /// What the host is still owed. The host's own slot counts as paid — they
  /// cannot pay themselves — so it is in the tally but not in the money.
  String get paymentLabel {
    final total = _deal.participantCount;
    final paid = _deal.paidCount;
    if (paid >= total) return 'Everyone has paid.';
    final owed = (total - paid) * _deal.pricePerShare;
    return '$paid of $total paid — ${formatPeso(owed)} still to collect';
  }

  /// Named in the cancel dialog before the host is allowed to go through with
  /// it. Null when there is nothing to hand back.
  String? get refundWarning {
    final students = _deal.studentsWhoPaid;
    if (students == 0) return null;
    final plural = students == 1 ? 'student has' : 'students have';
    return '$students $plural paid you ${formatPeso(_deal.amountHeld)}.';
  }

  Future<void> reserve() =>
      _mutate(() => _reservationRepository.reserveSlot(_deal.id));

  Future<void> cancel() =>
      _mutate(() => _reservationRepository.cancelReservation(_deal.id));

  Future<void> setPaid(String userId, {required bool paid}) => _mutate(
    () => _reservationRepository.setPaid(_deal.id, userId, paid: paid),
  );

  Future<void> setCollected(String userId, {required bool collected}) =>
      _mutate(
        () => _reservationRepository.setCollected(
          _deal.id,
          userId,
          collected: collected,
        ),
      );

  Future<void> markPurchased() =>
      _mutate(() => _reservationRepository.markPurchased(_deal.id));

  Future<void> cancelDeal() =>
      _mutate(() => _reservationRepository.cancelDeal(_deal.id));

  Future<void> retryParticipants() => _loadParticipants();

  /// Test seam: adopt a deal changed outside this ViewModel.
  void refreshDeal(Deal deal) {
    if (_isDisposed) return;
    _deal = deal;
    _dealGeneration++;
    _notifyListeners();
  }

  /// A second tap landing before the first call resolves would claim against a
  /// stale slot count. The button disables too; this is the backstop.
  Future<void> _mutate(Future<Deal> Function() action) async {
    if (_isUpdating || _isDisposed) return;

    final mutationGeneration = ++_mutationGeneration;
    final dealGeneration = _dealGeneration;
    _isUpdating = true;
    _errorMessage = null;
    _notifyListeners();

    try {
      late final Deal updatedDeal;
      try {
        updatedDeal = await action();
      } on ReservationFailure catch (failure) {
        if (_canCommitMutation(mutationGeneration, dealGeneration)) {
          _errorMessage = failure.message;
        }
        return;
      } catch (_) {
        if (_canCommitMutation(mutationGeneration, dealGeneration)) {
          _errorMessage = 'Could not update your slot. Please try again.';
        }
        return;
      }

      if (!_canCommitMutation(mutationGeneration, dealGeneration)) return;

      _deal = updatedDeal;
      _dealGeneration++;
      await _loadParticipants();
    } finally {
      if (!_isDisposed && mutationGeneration == _mutationGeneration) {
        _isUpdating = false;
        _notifyListeners();
      }
    }
  }

  Future<void> _loadParticipants() async {
    if (_isDisposed) return;

    final generation = ++_participantGeneration;
    _isLoadingParticipants = true;
    _participantErrorMessage = null;
    _notifyListeners();

    try {
      final participants = await _reservationRepository.getParticipants(
        _deal.id,
      );
      if (!_canCommitParticipants(generation)) return;

      _participants = participants;
      _isLoadingParticipants = false;
      _participantErrorMessage = null;
    } catch (_) {
      if (!_canCommitParticipants(generation)) return;

      _isLoadingParticipants = false;
      _participantErrorMessage =
          'Couldn’t load who is in this deal. Try again before reserving a slot.';
    }

    _notifyListeners();
  }

  bool _canCommitParticipants(int generation) =>
      !_isDisposed && generation == _participantGeneration;

  bool _canCommitMutation(int mutationGeneration, int dealGeneration) =>
      !_isDisposed &&
      mutationGeneration == _mutationGeneration &&
      dealGeneration == _dealGeneration;

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _participantGeneration++;
    _mutationGeneration++;
    super.dispose();
  }
}
