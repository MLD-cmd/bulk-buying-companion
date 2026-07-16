import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/notification_repository.dart';
import '../../models/deal_notification.dart';

class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel({
    required NotificationRepository notificationRepository,
    required this.hubId,
    required this.currentUserId,
  }) : _notificationRepository = notificationRepository {
    _subscription = _notificationRepository
        .watchNotifications(hubId: hubId, currentUserId: currentUserId)
        .listen(_setNotifications, onError: (_) => _setError());
  }

  final NotificationRepository _notificationRepository;
  final String hubId;
  final String currentUserId;

  List<DealNotification> _notifications = const [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDisposed = false;
  late final StreamSubscription<List<DealNotification>> _subscription;

  List<DealNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    _notifyIfAlive();

    try {
      _notifications = await _notificationRepository.getNotifications(
        hubId: hubId,
        currentUserId: currentUserId,
      );
    } catch (_) {
      _notifications = const [];
      _errorMessage = 'Could not load notifications. Please try again.';
    } finally {
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  void _setNotifications(List<DealNotification> notifications) {
    _notifications = notifications;
    _errorMessage = null;
    _isLoading = false;
    _notifyIfAlive();
  }

  void _setError() {
    _notifications = const [];
    _errorMessage = 'Could not load notifications. Please try again.';
    _isLoading = false;
    _notifyIfAlive();
  }

  void _notifyIfAlive() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
