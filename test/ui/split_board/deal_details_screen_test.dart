import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_screen.dart';
import 'package:bulk_buying_companion/ui/split_board/deal_details_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpDetails(
    WidgetTester tester,
    Deal deal, {
    String currentUserId = 'visitor',
  }) async {
    // Tall enough that the whole scrollable body — including the reserve
    // button below the new participants list — renders onstage, so plain
    // `find.text` / `find.byKey` see it without a manual scroll.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => DealDetailsViewModel(
            deal: deal,
            currentUserId: currentUserId,
            reservationRepository: MockReservationRepository(
              deal: deal,
              currentUserId: currentUserId,
            ),
          ),
          child: const DealDetailsScreen(),
        ),
      ),
    );
    // Lets the ViewModel's initial participants load resolve before assertions.
    await tester.pump();
  }

  Future<void> pumpDetailsWith(
    WidgetTester tester, {
    required MockReservationRepository repository,
    required String currentUserId,
  }) async {
    // Tall enough that the whole scrollable body renders onstage, so plain
    // find.text / find.byKey see it without a manual scroll.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => DealDetailsViewModel(
            deal: repository.deal,
            currentUserId: currentUserId,
            reservationRepository: repository,
          ),
          child: const DealDetailsScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<DealDetailsViewModel> pumpControlled(
    WidgetTester tester, {
    required _ScreenReservationRepository repository,
    required String currentUserId,
    Size size = const Size(800, 2400),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ChangeNotifierProvider(
          create: (_) => DealDetailsViewModel(
            deal: repository.deal,
            currentUserId: currentUserId,
            reservationRepository: repository,
          ),
          child: const DealDetailsScreen(),
        ),
      ),
    );

    return tester
        .element(find.byType(DealDetailsScreen))
        .read<DealDetailsViewModel>();
  }

  Deal hostedDeal({required int availableSlots, required int totalSlots}) {
    return Deal(
      id: 'd',
      hubId: 'h',
      createdBy: 'host',
      hostName: 'Marco Villanueva',
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

  testWidgets('participants move through loading, error, empty, and list', (
    tester,
  ) async {
    final repository = _ScreenReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    final viewModel = await pumpControlled(
      tester,
      repository: repository,
      currentUserId: 'ana',
    );

    expect(find.text('Loading participants…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Nobody has claimed a slot yet.'), findsNothing);

    repository.participantRequests.single.completeError(StateError('offline'));
    await tester.pump();

    expect(
      find.text(
        'Couldn’t load who is in this deal. Try again before reserving a slot.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Nobody has claimed a slot yet.'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Loading participants…'), findsOneWidget);
    expect(find.text('Nobody has claimed a slot yet.'), findsNothing);

    repository.participantRequests.last.complete(const []);
    await tester.pump();
    expect(find.text('Nobody has claimed a slot yet.'), findsOneWidget);

    final reload = viewModel.retryParticipants();
    await tester.pump();
    repository.participantRequests.last.complete([
      _screenReservation('ana', name: 'Ana Reyes'),
    ]);
    await reload;
    await tester.pump();

    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('Nobody has claimed a slot yet.'), findsNothing);
  });

  testWidgets('student action labels participant reliability', (tester) async {
    final repository = _ScreenReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    await pumpControlled(tester, repository: repository, currentUserId: 'ana');

    expect(find.text('Checking availability…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('detail-reserve-button')))
          .onPressed,
      isNull,
    );

    repository.participantRequests.single.completeError(StateError('offline'));
    await tester.pump();

    expect(find.text('Participants unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('detail-reserve-button')))
          .onPressed,
      isNull,
    );
    expect(find.text('Reserve a slot'), findsNothing);
    expect(find.text('Cancel my slot'), findsNothing);
  });

  testWidgets(
    'participant retry moves from failure through loading to a list',
    (tester) async {
      final repository = _ScreenReservationRepository(
        deal: hostedDeal(availableSlots: 3, totalSlots: 4),
        currentUserId: 'ana',
      );
      await pumpControlled(
        tester,
        repository: repository,
        currentUserId: 'ana',
      );
      repository.participantRequests.single.completeError(
        StateError('offline'),
      );
      await tester.pump();

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('Loading participants…'), findsOneWidget);
      expect(find.text('Nobody has claimed a slot yet.'), findsNothing);

      repository.participantRequests.last.complete([
        _screenReservation('ana', name: 'Ana Reyes'),
      ]);
      await tester.pump();

      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Cancel my slot'), findsOneWidget);
      expect(find.text('Nobody has claimed a slot yet.'), findsNothing);
    },
  );

  testWidgets('reserve success keeps the deal change when refresh fails', (
    tester,
  ) async {
    final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
    final repository = _ScreenReservationRepository(
      deal: deal,
      currentUserId: 'ana',
    );
    await pumpControlled(tester, repository: repository, currentUserId: 'ana');
    repository.participantRequests.single.complete(const []);
    await tester.pump();

    await tester.tap(find.byKey(const Key('detail-reserve-button')));
    repository.reserveRequest.complete(deal.copyWith(availableSlots: 2));
    await tester.pump();
    repository.participantRequests.last.completeError(StateError('offline'));
    await tester.pump();

    expect(find.text('2 of 4 slots open'), findsOneWidget);
    expect(find.byKey(const Key('detail-reservation-error')), findsNothing);
    expect(
      find.text(
        'Couldn’t load who is in this deal. Try again before reserving a slot.',
      ),
      findsOneWidget,
    );
    expect(find.text('Participants unavailable'), findsOneWidget);
  });

  testWidgets('cancel own slot requires one guarded confirmation', (
    tester,
  ) async {
    final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
    final repository = _ScreenReservationRepository(
      deal: deal,
      currentUserId: 'ana',
    );
    await pumpControlled(tester, repository: repository, currentUserId: 'ana');
    repository.participantRequests.single.complete([
      _screenReservation('ana', name: 'Ana Reyes'),
    ]);
    await tester.pump();

    final cancel = find.byKey(const Key('detail-reserve-button'));
    final cancelButton = tester.widget<OutlinedButton>(cancel);
    cancelButton.onPressed!();
    cancelButton.onPressed!();
    await tester.pump();

    expect(find.text('Cancel your slot?'), findsOneWidget);
    expect(
      find.text('Another hub member may take this slot after you cancel it.'),
      findsOneWidget,
    );
    expect(find.text('Keep slot'), findsOneWidget);
    expect(find.text('Cancel slot'), findsOneWidget);
    expect(repository.cancelCalls, 0);

    await tester.tap(find.text('Keep slot'));
    await tester.pumpAndSettle();
    expect(repository.cancelCalls, 0);

    await tester.tap(cancel);
    await tester.pump();
    await tester.tap(find.text('Cancel slot'));
    await tester.pump();
    expect(repository.cancelCalls, 1);
  });

  testWidgets(
    'cancel confirmation cannot act after participant state changes',
    (tester) async {
      final repository = _ScreenReservationRepository(
        deal: hostedDeal(availableSlots: 3, totalSlots: 4),
        currentUserId: 'ana',
      );
      final viewModel = await pumpControlled(
        tester,
        repository: repository,
        currentUserId: 'ana',
      );
      repository.participantRequests.single.complete([
        _screenReservation('ana', name: 'Ana Reyes'),
      ]);
      await tester.pump();

      await tester.tap(find.byKey(const Key('detail-reserve-button')));
      await tester.pump();
      final reload = viewModel.retryParticipants();
      await tester.tap(find.text('Cancel slot'));
      await tester.pump();

      expect(repository.cancelCalls, 0);
      repository.participantRequests.last.complete(const []);
      await reload;
    },
  );

  testWidgets('mark purchased requires one guarded confirmation', (
    tester,
  ) async {
    final deal = hostedDeal(availableSlots: 0, totalSlots: 2);
    final repository = _ScreenReservationRepository(
      deal: deal,
      currentUserId: 'host',
    );
    await pumpControlled(tester, repository: repository, currentUserId: 'host');
    repository.participantRequests.single.complete([
      _screenReservation('host', name: 'Marco', isHost: true, paid: true),
      _screenReservation('ana', name: 'Ana'),
    ]);
    await tester.pump();

    final purchase = find.byKey(const Key('detail-mark-purchased-button'));
    final purchaseButton = tester.widget<FilledButton>(purchase);
    purchaseButton.onPressed!();
    purchaseButton.onPressed!();
    await tester.pump();

    expect(find.text('Mark this deal as purchased?'), findsOneWidget);
    expect(
      find.text('Reservations will be locked after you confirm the purchase.'),
      findsOneWidget,
    );
    expect(find.text('Not yet'), findsOneWidget);
    expect(find.text('I’ve bought it'), findsOneWidget);
    expect(repository.markPurchasedCalls, 0);

    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(repository.markPurchasedCalls, 0);

    await tester.tap(purchase);
    await tester.pump();
    await tester.tap(find.text('I’ve bought it'));
    await tester.pump();
    expect(repository.markPurchasedCalls, 1);
  });

  testWidgets(
    'help is accessible and preserves deal participant and scroll state',
    (tester) async {
      final repository = _ScreenReservationRepository(
        deal: hostedDeal(availableSlots: 3, totalSlots: 4),
        currentUserId: 'ana',
      );
      final viewModel = await pumpControlled(
        tester,
        repository: repository,
        currentUserId: 'ana',
        size: const Size(800, 900),
      );
      repository.participantRequests.single.complete([
        _screenReservation('ana', name: 'Ana Reyes'),
      ]);
      await tester.pump();

      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      await tester.pump();
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scrollable.position.pixels;
      final dealBefore = viewModel.deal;
      final participantsBefore = viewModel.participants;

      final help = find.byTooltip('How deal details work');
      expect(help, findsOneWidget);
      expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(help).label,
        contains('How deal details work'),
      );

      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(find.text('How deal details work'), findsOneWidget);
      expect(find.text('Payment and your share'), findsOneWidget);
      expect(find.text('Slots and pickup'), findsOneWidget);
      expect(find.text('Reserve or manage'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(viewModel.deal, same(dealBefore));
      expect(viewModel.participants, same(participantsBefore));
      expect(scrollable.position.pixels, offset);
      expect(find.byType(DealDetailsScreen), findsOneWidget);
    },
  );

  testWidgets('participant failure and help fit at 320dp and 200 percent', (
    tester,
  ) async {
    final repository = _ScreenReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    await pumpControlled(
      tester,
      repository: repository,
      currentUserId: 'ana',
      size: const Size(320, 900),
      textScale: 2,
    );
    repository.participantRequests.single.completeError(StateError('offline'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('How deal details work'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading action and help fit in landscape', (tester) async {
    final repository = _ScreenReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    await pumpControlled(
      tester,
      repository: repository,
      currentUserId: 'ana',
      size: const Size(900, 320),
    );

    expect(find.text('Loading participants…'), findsOneWidget);
    expect(find.text('Checking availability…'), findsOneWidget);
    expect(find.byTooltip('How deal details work'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removal during dialog or mutation avoids stale context work', (
    tester,
  ) async {
    final deal = hostedDeal(availableSlots: 3, totalSlots: 4);
    final repository = _ScreenReservationRepository(
      deal: deal,
      currentUserId: 'ana',
    );
    await pumpControlled(tester, repository: repository, currentUserId: 'ana');
    repository.participantRequests.single.complete([
      _screenReservation('ana', name: 'Ana'),
    ]);
    await tester.pump();
    await tester.tap(find.byKey(const Key('detail-reserve-button')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(repository.cancelCalls, 0);
    expect(tester.takeException(), isNull);

    final helpRepository = _ScreenReservationRepository(
      deal: deal,
      currentUserId: 'ana',
    );
    await pumpControlled(
      tester,
      repository: helpRepository,
      currentUserId: 'ana',
    );
    helpRepository.participantRequests.single.complete(const []);
    await tester.pump();
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.help_outline))
        .onPressed!();
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final mutationRepository = _ScreenReservationRepository(
      deal: deal,
      currentUserId: 'bea',
    );
    await pumpControlled(
      tester,
      repository: mutationRepository,
      currentUserId: 'bea',
    );
    mutationRepository.participantRequests.single.complete(const []);
    await tester.pump();
    tester
        .widget<FilledButton>(find.byKey(const Key('detail-reserve-button')))
        .onPressed!();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    mutationRepository.reserveRequest.complete(
      deal.copyWith(availableSlots: 2),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the product, host, cost, slots and pickup details', (
    tester,
  ) async {
    await pumpDetails(tester, _deal);

    // Product information.
    expect(find.text('25kg Rice Sack'), findsOneWidget);
    expect(find.text('Sinandomeng, from the Carbon market'), findsOneWidget);
    expect(find.text('Grocery'), findsOneWidget);
    expect(find.text('1 kg'), findsOneWidget);

    // Host information.
    expect(find.text('Marco Villanueva'), findsOneWidget);

    // Cost per slot: P900 split 5 ways.
    expect(find.text('P180'), findsOneWidget);
    expect(find.text('Total P900'), findsOneWidget);
    expect(find.text('split 5 ways'), findsOneWidget);

    // Available slots.
    expect(find.text('3 of 5 slots open'), findsOneWidget);
    expect(find.text('2 of 5 already claimed'), findsOneWidget);
    expect(find.byKey(const Key('detail-action-bar')), findsOneWidget);
    final slotProgress = tester.getSemantics(
      find.byKey(const Key('detail-slot-progress')),
    );
    expect(slotProgress.label, contains('2 of 5 slots claimed'));
    expect(slotProgress.flagsCollection.isReadOnly, isTrue);

    // Pickup details.
    expect(find.text('USJR Main Gate'), findsOneWidget);
    expect(find.text('Closes 7/16/2026'), findsOneWidget);

    // Reservation button.
    expect(find.text('Reserve a slot'), findsOneWidget);
  });

  testWidgets('details reflow at narrow width with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => DealDetailsViewModel(
            deal: _reservableDeal,
            currentUserId: 'user-2',
            reservationRepository: MockReservationRepository(
              deal: _reservableDeal,
              currentUserId: 'user-2',
            ),
          ),
          child: const DealDetailsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('detail-participants')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the whole buy on the pill, not a meaningless unit count', (
    tester,
  ) async {
    await pumpDetails(tester, _bulk);

    expect(find.text('24 bottles'), findsOneWidget);
  });

  testWidgets('names a host with no profile rather than leaving a gap', (
    tester,
  ) async {
    await pumpDetails(tester, _hostless);

    expect(find.text('A student in this hub'), findsOneWidget);
  });

  testWidgets('omits the description when there is none', (tester) async {
    await pumpDetails(tester, _hostless);

    expect(find.byKey(const Key('detail-description')), findsNothing);
  });

  testWidgets('disables reserving once the deal is full', (tester) async {
    await pumpDetails(tester, _full);

    expect(find.text('No slots left'), findsOneWidget);
    expect(find.text('0 of 3 slots open'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('detail-reserve-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('states the surplus when the split is uneven', (tester) async {
    await pumpDetails(tester, _uneven);

    expect(find.text('P128.58'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsOneWidget);
  });

  testWidgets('shows what a student receives, not just what they pay', (
    tester,
  ) async {
    await pumpDetails(tester, _uneven);

    // The whole buy — not "1 unit".
    expect(find.text('25 kg'), findsOneWidget);
    expect(find.byKey(const Key('detail-physical-share')), findsOneWidget);
    expect(find.text('3.57 kg'), findsOneWidget);
  });

  testWidgets('says nothing about surplus on an even split', (tester) async {
    await pumpDetails(tester, _deal);

    expect(find.text('P180'), findsOneWidget);
    expect(find.byKey(const Key('detail-split-surplus')), findsNothing);
  });

  testWidgets('a student can take a slot', (tester) async {
    await pumpDetails(tester, _reservableDeal, currentUserId: 'user-2');

    expect(find.text('Reserve a slot'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-reserve-button')));
    await tester.pumpAndSettle();

    expect(find.text('Cancel my slot'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(
        find.byKey(const Key('detail-reserve-button')),
      ),
      isA<OutlinedButton>(),
    );
  });

  testWidgets('the host is shown holding a slot they cannot give up', (
    tester,
  ) async {
    await pumpDetails(tester, _reservableDeal, currentUserId: 'user-1');

    expect(find.byKey(const Key('detail-host-slot-note')), findsOneWidget);
    expect(find.text('Cancel my slot'), findsNothing);
  });

  testWidgets('lists who is in the buy', (tester) async {
    await pumpDetails(tester, _reservableDeal, currentUserId: 'user-2');

    final participants = find.byKey(const Key('detail-participants'));
    expect(participants, findsOneWidget);
    expect(
      find.descendant(
        of: participants,
        matching: find.text('Marco Villanueva'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: participants, matching: find.text('(organiser)')),
      findsOneWidget,
    );

    final organiser = tester.widget<Text>(
      find.descendant(of: participants, matching: find.text('(organiser)')),
    );
    expect(
      organiser.style?.color,
      isNotNull,
      reason: 'The organiser note should stay visually quieter than the name.',
    );
  });

  testWidgets('the host sees who has paid, and what is left to collect', (
    tester,
  ) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    expect(find.text('1 of 2 paid — P100 still to collect'), findsOneWidget);
    expect(find.byKey(const Key('mark-paid-ana')), findsOneWidget);

    // The host cannot unpay themselves: their own row is a bare chip, never a
    // button. This widget-level guard is the only thing enforcing that.
    expect(find.byKey(const Key('mark-paid-host')), findsNothing);

    await tester.tap(find.byKey(const Key('mark-paid-ana')));
    await tester.pumpAndSettle();

    expect(find.text('Everyone has paid.'), findsOneWidget);
  });

  testWidgets('a student sees the state but cannot change it', (tester) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'ana',
    );
    await repository.reserveSlotFor('ana');

    await pumpDetailsWith(tester, repository: repository, currentUserId: 'ana');

    expect(find.byKey(const Key('mark-paid-ana')), findsNothing);
    expect(find.byKey(const Key('detail-mark-purchased-button')), findsNothing);
    expect(find.byKey(const Key('detail-cancel-deal-button')), findsNothing);
  });

  testWidgets('cancelling warns the host what they owe back', (tester) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.markPaidForTest('ana');

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    final cancelButton = find.byKey(const Key('detail-cancel-deal-button'));
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(find.text('1 student has paid you P100.'), findsOneWidget);
    expect(
      find.text(
        'Cancelling does not refund them — you will have to hand it back '
        'yourself.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel the deal'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('the host can back out of cancelling', (tester) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 3, totalSlots: 4),
      currentUserId: 'host',
    );

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    final cancelButton = find.byKey(const Key('detail-cancel-deal-button'));
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep the deal'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('collection stays hidden until the goods are bought', (
    tester,
  ) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    // Not bought yet, so there is nothing to collect.
    expect(find.byKey(const Key('mark-collected-ana')), findsNothing);
    expect(find.text('Collected'), findsNothing);
    expect(find.text('Mark collected'), findsNothing);
  });

  testWidgets('once bought, the host ticks off who has collected', (
    tester,
  ) async {
    final repository = MockReservationRepository(
      deal: hostedDeal(availableSlots: 1, totalSlots: 2),
      currentUserId: 'host',
    );
    await repository.reserveSlotFor('ana');
    await repository.markPurchased('d');

    await pumpDetailsWith(
      tester,
      repository: repository,
      currentUserId: 'host',
    );

    final anaCollected = find.byKey(const Key('mark-collected-ana'));
    expect(anaCollected, findsOneWidget);
    // The host's own share is collected the moment they buy; Ana's is not.
    expect(find.text('Mark collected'), findsOneWidget);

    await tester.tap(anaCollected);
    await tester.pumpAndSettle();

    expect(find.text('Mark collected'), findsNothing);
    expect(
      find.descendant(of: anaCollected, matching: find.text('Collected')),
      findsOneWidget,
    );
  });
}

Reservation _screenReservation(
  String userId, {
  required String name,
  bool isHost = false,
  bool paid = false,
}) {
  return Reservation(
    dealId: 'd',
    userId: userId,
    studentName: name,
    isHost: isHost,
    reservedAt: DateTime(2026, 7, 14),
    paidAt: paid ? DateTime(2026, 7, 14) : null,
  );
}

class _ScreenReservationRepository implements ReservationRepository {
  _ScreenReservationRepository({
    required Deal deal,
    required String currentUserId,
  }) : _deal = deal,
       _delegate = MockReservationRepository(
         deal: deal,
         currentUserId: currentUserId,
       );

  final Deal _deal;
  final MockReservationRepository _delegate;
  final List<Completer<List<Reservation>>> participantRequests = [];
  final Completer<Deal> reserveRequest = Completer<Deal>();
  final Completer<Deal> cancelRequest = Completer<Deal>();
  final Completer<Deal> markPurchasedRequest = Completer<Deal>();
  int cancelCalls = 0;
  int markPurchasedCalls = 0;

  Deal get deal => _deal;

  @override
  Future<List<Reservation>> getParticipants(String dealId) {
    final request = Completer<List<Reservation>>();
    participantRequests.add(request);
    return request.future;
  }

  @override
  Future<Deal> reserveSlot(String dealId) => reserveRequest.future;

  @override
  Future<Deal> cancelReservation(String dealId) {
    cancelCalls++;
    return cancelRequest.future;
  }

  @override
  Future<Deal> markPurchased(String dealId) {
    markPurchasedCalls++;
    return markPurchasedRequest.future;
  }

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
  Future<Deal> cancelDeal(String dealId) => _delegate.cancelDeal(dealId);
}

final _deal = Deal(
  id: 'colon-rice',
  hubId: 'colon',
  title: '25kg Rice Sack',
  description: 'Sinandomeng, from the Carbon market',
  hostName: 'Marco Villanueva',
  category: DealCategory.grocery,
  totalPrice: 900,
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
  closesAt: DateTime(2026, 7, 16, 23, 59),
);

const _bulk = Deal(
  id: 'colon-water',
  hubId: 'colon',
  title: 'Bottled Water Case',
  hostName: 'Bea Alonzo',
  category: DealCategory.drinks,
  totalPrice: 380,
  amount: 24,
  unit: DealUnit.bottles,
  availableSlots: 2,
  totalSlots: 4,
  pickupLocation: 'Colon Street Hub',
);

/// A deal whose host has no profile row — the left join in deal_feed returns
/// the deal with a null host_name rather than dropping it.
const _hostless = Deal(
  id: 'orphan',
  hubId: 'colon',
  title: 'Cooking Oil 5L',
  category: DealCategory.pantry,
  totalPrice: 750,
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 5,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);

const _uneven = Deal(
  id: 'colon-rice-7',
  hubId: 'colon',
  title: '25kg Rice Sack',
  hostName: 'Marco Villanueva',
  category: DealCategory.grocery,
  totalPrice: 900,
  amount: 25,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 7,
  pickupLocation: 'USJR Main Gate',
);

const _full = Deal(
  id: 'colon-detergent',
  hubId: 'colon',
  title: 'Laundry Detergent 6L',
  hostName: 'Rey Mercado',
  category: DealCategory.household,
  totalPrice: 360,
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 0,
  totalSlots: 3,
  pickupLocation: 'Barangay Hall Lobby',
);

/// Used by the reservation tests: needs a real [createdBy] so the host rules
/// (already holds a slot, cannot cancel) actually engage.
const _reservableDeal = Deal(
  id: 'colon-rice-reservable',
  hubId: 'colon',
  title: '25kg Rice Sack',
  createdBy: 'user-1',
  hostName: 'Marco Villanueva',
  category: DealCategory.grocery,
  totalPrice: 900,
  amount: 1,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);
