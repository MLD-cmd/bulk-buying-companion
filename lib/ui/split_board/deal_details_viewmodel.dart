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
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _errorMessage;

  Deal get deal => _deal;
  List<Reservation> get participants => _participants;
  bool get isLoading => _isLoading;
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

  /// The host is the person everyone else is relying on, so they cannot walk
  /// away from their own buy; and past the deadline the host is about to spend
  /// real money against a count that must now be final.
  bool get canCancel => holdsSlot && !isHost && !deadlinePassed;

  bool get canReserve => !holdsSlot && !isFull && !deadlinePassed;

  Future<void> reserve() =>
      _mutate(() => _reservationRepository.reserveSlot(_deal.id));

  Future<void> cancel() =>
      _mutate(() => _reservationRepository.cancelReservation(_deal.id));

  /// A second tap landing before the first call resolves would claim against a
  /// stale slot count. The button disables too; this is the backstop.
  Future<void> _mutate(Future<Deal> Function() action) async {
    if (_isUpdating) return;

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _deal = await action();
      _participants = await _reservationRepository.getParticipants(_deal.id);
    } on ReservationFailure catch (failure) {
      _errorMessage = failure.message;
    } catch (_) {
      _errorMessage = 'Could not update your slot. Please try again.';
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<void> _loadParticipants() async {
    try {
      _participants = await _reservationRepository.getParticipants(_deal.id);
    } catch (_) {
      _participants = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
