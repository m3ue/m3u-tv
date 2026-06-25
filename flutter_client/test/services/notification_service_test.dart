import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/notification_service.dart';

void main() {
  group('AppNotificationService', () {
    test('publish stores metadata and notifies listeners', () async {
      final service = AppNotificationService(clock: () => DateTime(2026));
      addTearDown(service.dispose);

      final updates = <List<AppNotification>>[];
      final subscription = service.notificationsStream.listen(updates.add);
      addTearDown(subscription.cancel);

      final notification = service.publish(
        severity: AppNotificationSeverity.success,
        title: 'Cache cleared',
        message: 'Content is refreshing in the background.',
        source: 'settings',
        category: 'cache',
        action: const AppNotificationAction(
          label: 'Open settings',
          deepLink: '/settings',
        ),
      );

      await pumpEventQueue();

      expect(service.notifications, [notification]);
      expect(updates.single, [notification]);
      expect(notification.severity, AppNotificationSeverity.success);
      expect(notification.title, 'Cache cleared');
      expect(notification.message, 'Content is refreshing in the background.');
      expect(notification.source, 'settings');
      expect(notification.category, 'cache');
      expect(notification.timestamp, DateTime(2026));
      expect(notification.action?.label, 'Open settings');
      expect(notification.action?.deepLink, '/settings');
    });

    test(
      'dismiss removes one notification and emits the updated store',
      () async {
        final service = AppNotificationService(clock: () => DateTime(2026));
        addTearDown(service.dispose);
        final updates = <List<AppNotification>>[];
        final subscription = service.notificationsStream.listen(updates.add);
        addTearDown(subscription.cancel);

        final first = service.publish(
          severity: AppNotificationSeverity.info,
          title: 'First',
          message: 'One',
          source: 'test',
        );
        final second = service.publish(
          severity: AppNotificationSeverity.warning,
          title: 'Second',
          message: 'Two',
          source: 'test',
        );

        service.dismiss(first.id);
        await pumpEventQueue();

        expect(service.notifications, [second]);
        expect(updates.last, [second]);
      },
    );

    test('clear removes every notification and emits an empty store', () async {
      final service = AppNotificationService(clock: () => DateTime(2026));
      addTearDown(service.dispose);
      final updates = <List<AppNotification>>[];
      final subscription = service.notificationsStream.listen(updates.add);
      addTearDown(subscription.cancel);

      service
        ..publish(
          severity: AppNotificationSeverity.info,
          title: 'First',
          message: 'One',
          source: 'test',
        )
        ..publish(
          severity: AppNotificationSeverity.error,
          title: 'Second',
          message: 'Two',
          source: 'test',
        )
        ..clear();
      await pumpEventQueue();

      expect(service.notifications, isEmpty);
      expect(updates.last, isEmpty);
    });
  });
}
