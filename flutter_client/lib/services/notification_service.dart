import 'dart:async';

import 'package:flutter/foundation.dart';

enum AppNotificationSeverity { info, success, warning, error }

class AppNotificationAction {
  const AppNotificationAction({required this.label, required this.deepLink});

  final String label;
  final String deepLink;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.severity,
    required this.title,
    required this.message,
    required this.source,
    required this.timestamp,
    this.category,
    this.action,
  });

  final String id;
  final AppNotificationSeverity severity;
  final String title;
  final String message;
  final String source;
  final String? category;
  final DateTime timestamp;
  final AppNotificationAction? action;
}

class AppNotificationService extends ChangeNotifier {
  AppNotificationService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _controller = StreamController<List<AppNotification>>.broadcast();
  final List<AppNotification> _notifications = <AppNotification>[];
  var _nextId = 0;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  Stream<List<AppNotification>> get notificationsStream => _controller.stream;

  AppNotification publish({
    required AppNotificationSeverity severity,
    required String title,
    required String message,
    required String source,
    String? category,
    AppNotificationAction? action,
  }) {
    _nextId += 1;
    final notification = AppNotification(
      id: 'notification-$_nextId',
      severity: severity,
      title: title,
      message: message,
      source: source,
      category: category,
      timestamp: _clock(),
      action: action,
    );
    _notifications.add(notification);
    _emit();
    return notification;
  }

  void dismiss(String id) {
    final before = _notifications.length;
    _notifications.removeWhere((notification) => notification.id == id);
    if (_notifications.length != before) _emit();
  }

  void clear() {
    if (_notifications.isEmpty) return;
    _notifications.clear();
    _emit();
  }

  void _emit() {
    final snapshot = notifications;
    _controller.add(snapshot);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }
}
