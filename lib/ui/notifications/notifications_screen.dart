import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../models/deal_notification.dart';
import '../shared/app_icon_container.dart';
import '../shared/app_message_state.dart';
import '../shared/app_theme.dart';
import 'notifications_viewmodel.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.hubName});

  final String hubName;

  static Route<void> route({required String hubId, required String hubName}) {
    return MaterialPageRoute(
      builder: (context) {
        final user = context.read<AuthRepository>().currentUser;
        if (user == null) {
          return const _SignedOutNotificationsScreen();
        }

        return ChangeNotifierProvider(
          create: (context) => NotificationsViewModel(
            notificationRepository: context.read<NotificationRepository>(),
            hubId: hubId,
            currentUserId: user.uid,
          ),
          child: NotificationsScreen(hubName: hubName),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Notifications'),
            const SizedBox(height: 2),
            Text(
              hubName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Consumer<NotificationsViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: viewModel.refresh,
              child: viewModel.hasError
                  ? AppMessageState(
                      icon: Icons.notifications_off_outlined,
                      title: "Couldn't load notifications",
                      message: viewModel.errorMessage!,
                      onRetry: viewModel.refresh,
                    )
                  : viewModel.notifications.isEmpty
                  ? const AppMessageState(
                      icon: Icons.notifications_none_outlined,
                      title: 'No notifications yet',
                      message:
                          'Reservation updates, payment reminders, pickup reminders, and cancellations will appear here.',
                    )
                  : _NotificationList(notifications: viewModel.notifications),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.notifications});

  final List<DealNotification> notifications;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: notifications.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _NotificationCard(notification: notifications[index]);
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final DealNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _NotificationColors.forKind(context, notification.kind);

    return Card(
      key: Key('notification-card-${notification.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconContainer(
              icon: _iconFor(notification.kind),
              backgroundColor: colors.background,
              foregroundColor: colors.foreground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(DealNotificationKind kind) {
    return switch (kind) {
      DealNotificationKind.reservationUpdate => Icons.person_add_alt_1_outlined,
      DealNotificationKind.dealFull => Icons.groups_2_outlined,
      DealNotificationKind.paymentReminder => Icons.payments_outlined,
      DealNotificationKind.pickupReminder => Icons.shopping_bag_outlined,
      DealNotificationKind.itemCollected => Icons.task_alt_outlined,
      DealNotificationKind.cancellation => Icons.cancel_outlined,
    };
  }
}

class _NotificationColors {
  const _NotificationColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  static _NotificationColors forKind(
    BuildContext context,
    DealNotificationKind kind,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return switch (kind) {
      DealNotificationKind.paymentReminder =>
        theme.brightness == Brightness.light
            ? const _NotificationColors(
                background: AppTheme.warningContainer,
                foreground: AppTheme.onWarningContainer,
              )
            : _NotificationColors(
                background: scheme.tertiaryContainer,
                foreground: scheme.onTertiaryContainer,
              ),
      DealNotificationKind.cancellation => _NotificationColors(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      ),
      DealNotificationKind.pickupReminder =>
        theme.brightness == Brightness.light
            ? const _NotificationColors(
                background: AppTheme.successContainer,
                foreground: AppTheme.onSuccessContainer,
              )
            : _NotificationColors(
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
              ),
      DealNotificationKind.itemCollected => _NotificationColors(
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      ),
      DealNotificationKind.reservationUpdate ||
      DealNotificationKind.dealFull => _NotificationColors(
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      ),
    };
  }
}

class _SignedOutNotificationsScreen extends StatelessWidget {
  const _SignedOutNotificationsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const SafeArea(
        child: AppMessageState(
          icon: Icons.person_off_outlined,
          title: 'Not signed in',
          message: 'Return to login to view notifications.',
        ),
      ),
    );
  }
}
