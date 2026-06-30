import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

// M3 buttons use StadiumBorder. A large radius makes the dpad focus border
// match the pill shape regardless of widget height.
const _kStadiumEffect = [
  GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
];

/// Lists TV push notifications with local read/unread state, letting the
/// user flip through history and mark items (or everything) as read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.appState});

  final AppStateController appState;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<StoredTvNotification> _notifications = const <StoredTvNotification>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    widget.appState.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final notifications = await widget.appState.notificationStore.all();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _loaded = true;
    });
  }

  Future<void> _markRead(StoredTvNotification notification) async {
    if (notification.isRead) return;
    await widget.appState.markNotificationRead(notification.item.id);
    await _reload();
  }

  Future<void> _markAllRead() async {
    await widget.appState.markAllNotificationsRead();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Notifications', style: theme.textTheme.headlineMedium),
                const Spacer(),
                if (hasUnread)
                  DpadFocusable(
                    onSelect: _markAllRead,
                    effects: _kStadiumEffect,
                    child: FilledButton.tonalIcon(
                      onPressed: _markAllRead,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Mark all read'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_notifications.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'No notifications yet',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _notifications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _NotificationTile(
                      notification: _notifications[index],
                      onTap: () => _markRead(_notifications[index]),
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final StoredTvNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = notification.item;
    final (icon, color) = switch (item.status) {
      'success' => (Icons.check_circle, theme.colorScheme.primary),
      'warning' => (Icons.warning_amber, Colors.amber),
      'danger' => (Icons.error, theme.colorScheme.error),
      _ => (Icons.info, theme.colorScheme.secondary),
    };

    return DpadInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: notification.isRead
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(
            item.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: notification.isRead
                  ? FontWeight.normal
                  : FontWeight.w700,
            ),
          ),
          subtitle: item.body != null && item.body!.isNotEmpty
              ? Text(item.body!)
              : null,
          trailing: notification.isRead
              ? null
              : Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}
