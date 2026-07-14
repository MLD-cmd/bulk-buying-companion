import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
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
    status: DealStatus.open,
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
