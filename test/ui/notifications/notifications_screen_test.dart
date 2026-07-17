import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/notification_repository.dart';
import 'package:bulk_buying_companion/models/deal_notification.dart';
import 'package:bulk_buying_companion/ui/notifications/notifications_screen.dart';
import 'package:bulk_buying_companion/ui/notifications/notifications_viewmodel.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('shows reminder cards for the current hub', (tester) async {
    final viewModel = NotificationsViewModel(
      notificationRepository: const _NotificationStub([
        DealNotification(
          id: 'rice-payment',
          dealId: 'rice',
          kind: DealNotificationKind.paymentReminder,
          title: 'Payment reminder',
          message: 'Pay P100 for Rice Sack before 7/20/2026.',
        ),
        DealNotification(
          id: 'water-pickup',
          dealId: 'water',
          kind: DealNotificationKind.pickupReminder,
          title: 'Pickup reminder',
          message: 'Pick up Water Case at Campus Gate.',
        ),
      ]),
      hubId: 'colon',
      currentUserId: 'ana',
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NotificationsScreen(hubName: 'Colon Hub'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Colon Hub'), findsOneWidget);
    expect(find.text('Payment reminder'), findsOneWidget);
    expect(find.text('Pickup reminder'), findsOneWidget);
    expect(
      find.byKey(const Key('notification-card-rice-payment')),
      findsOneWidget,
    );
  });

  testWidgets('updates cards when realtime notifications arrive', (
    tester,
  ) async {
    final controller = StreamController<List<DealNotification>>();
    final viewModel = NotificationsViewModel(
      notificationRepository: _StreamingNotificationStub(controller.stream),
      hubId: 'colon',
      currentUserId: 'ana',
    );
    addTearDown(viewModel.dispose);
    addTearDown(controller.close);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NotificationsScreen(hubName: 'Colon Hub'),
        ),
      ),
    );

    controller.add(const [
      DealNotification(
        id: 'rice-payment',
        dealId: 'rice',
        kind: DealNotificationKind.paymentReminder,
        title: 'Payment reminder',
        message: 'Pay P100 for Rice Sack before 7/20/2026.',
      ),
    ]);
    await tester.pump();

    expect(find.text('Payment reminder'), findsOneWidget);
    expect(find.text('Pickup reminder'), findsNothing);

    controller.add(const [
      DealNotification(
        id: 'water-pickup',
        dealId: 'water',
        kind: DealNotificationKind.pickupReminder,
        title: 'Pickup reminder',
        message: 'Pick up Water Case at Campus Gate.',
      ),
    ]);
    await tester.pump();

    expect(find.text('Payment reminder'), findsNothing);
    expect(find.text('Pickup reminder'), findsOneWidget);
  });
}

class _NotificationStub implements NotificationRepository {
  const _NotificationStub(this.notifications);

  final List<DealNotification> notifications;

  @override
  Future<List<DealNotification>> getNotifications({
    required String hubId,
    required String currentUserId,
  }) async {
    return notifications;
  }

  @override
  Stream<List<DealNotification>> watchNotifications({
    required String hubId,
    required String currentUserId,
  }) {
    return Stream.value(notifications);
  }
}

class _StreamingNotificationStub implements NotificationRepository {
  const _StreamingNotificationStub(this.stream);

  final Stream<List<DealNotification>> stream;

  @override
  Future<List<DealNotification>> getNotifications({
    required String hubId,
    required String currentUserId,
  }) async {
    return const [];
  }

  @override
  Stream<List<DealNotification>> watchNotifications({
    required String hubId,
    required String currentUserId,
  }) {
    return stream;
  }
}
