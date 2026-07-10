import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/tv_notification_store.dart'
    show StoredTvNotification, TvNotificationChannel, TvNotificationStore;
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

const _kStadiumEffect = [
  GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
];

/// Lists TV push notifications with local read/unread state, letting the
/// user flip through history, mark items as read, and configure channel
/// subscriptions.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onSetChannels,
  });

  final Future<void> Function(String id) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function(Set<String> channels) onSetChannels;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);
  late final TvNotificationStore _store;
  List<StoredTvNotification> _notifications = const [];
  Set<String> _subscribed = const {};
  List<TvNotificationChannel> _knownChannels = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _store = ref.read(notificationStoreProvider);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final results = await Future.wait([
      _store.all(),
      _store.subscribedChannels(),
      _store.knownChannels(),
    ]);
    if (!mounted) return;
    setState(() {
      _notifications = results[0] as List<StoredTvNotification>;
      _subscribed = results[1] as Set<String>;
      _knownChannels = results[2] as List<TvNotificationChannel>;
      _loaded = true;
    });
  }

  Future<void> _markRead(StoredTvNotification notification) async {
    if (notification.isRead) return;
    await widget.onMarkRead(notification.item.id);
  }

  Future<void> _markAllRead() async {
    await widget.onMarkAllRead();
  }

  Future<void> _toggleChannel(String channel) async {
    final next = Set<String>.from(_subscribed);
    if (next.contains(channel)) {
      next.remove(channel);
    } else {
      next.add(channel);
    }
    await widget.onSetChannels(next);
  }

  Future<void> _clearChannelFilter() async {
    await widget.onSetChannels({});
  }

  @override
  Widget build(BuildContext context) {
    // Reload whenever AppStateController notifies — covers incoming
    // notifications, markRead mutations, and subscription changes.
    ref.listen(appStateControllerProvider, (_, _) => unawaited(_reload()));

    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Text(
              l.notificationsTitle,
              style: theme.textTheme.headlineMedium,
            ),
          ),
          DpadTabBar(
            controller: _tabController,
            tabs: [
              l.notificationsTabNotifications,
              l.notificationsTabChannelSettings,
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildNotificationsTab(theme),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildSettingsTab(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final filtered = _subscribed.isEmpty
        ? _notifications
        : _notifications
              .where((n) => _subscribed.contains(n.item.channel))
              .toList(growable: false);
    final hasUnread = filtered.any((n) => !n.isRead);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasUnread)
          Align(
            alignment: Alignment.centerRight,
            child: DpadFocusable(
              onSelect: _markAllRead,
              effects: _kStadiumEffect,
              child: FilledButton.tonalIcon(
                onPressed: _markAllRead,
                icon: const Icon(Icons.done_all),
                label: Text(l.notificationsMarkAllRead),
              ),
            ),
          ),
        if (hasUnread) const SizedBox(height: 12),
        if (!_loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                _notifications.isEmpty
                    ? l.notificationsEmpty
                    : l.notificationsEmptyFiltered,
                style: theme.textTheme.titleMedium,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _NotificationTile(
              notification: filtered[index],
              onTap: () => _markRead(filtered[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsTab(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.notificationsChannelSubscriptions,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l.notificationsChannelSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (!_loaded)
          const Center(child: CircularProgressIndicator())
        else ...[
          _ChannelFilterChip(
            label: l.notificationsAllChannels,
            isSelected: _subscribed.isEmpty,
            onTap: _clearChannelFilter,
          ),
          if (_knownChannels.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final channel in _knownChannels)
                  _ChannelFilterChip(
                    label: channel.displayName,
                    isSelected: _subscribed.contains(channel.name),
                    onTap: () => _toggleChannel(channel.name),
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                l.notificationsNoChannels,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── Channel filter chips ─────────────────────────────────────────────────────

class _ChannelFilterChip extends StatelessWidget {
  const _ChannelFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(20));
  static const _effects = [GradientBorderEffect(borderRadius: _radius)];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      onTap: onTap,
      effects: _effects,
      color: isSelected
          ? colorScheme.secondaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: _radius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check : Icons.add,
              size: 16,
              color: isSelected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isSelected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification tile ────────────────────────────────────────────────────────

String _formatTimestamp(AppLocalizations l, DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) return l.notificationsJustNow;
  if (diff.inMinutes < 60) return l.notificationsMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l.notificationsHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l.notificationsDaysAgo(diff.inDays);
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$month-$day';
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final StoredTvNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final item = notification.item;
    final dimStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final (icon, color) = switch (item.status) {
      'success' => (Icons.check_circle, theme.colorScheme.primary),
      'warning' => (Icons.warning_amber, Colors.amber),
      'danger' => (Icons.error, theme.colorScheme.error),
      _ => (Icons.info, theme.colorScheme.secondary),
    };
    final receivedStr = l.notificationsReceivedAt(
      _formatTimestamp(l, notification.receivedAt),
    );
    final readStr = notification.readAt != null
        ? ' · ${l.notificationsReadAt(_formatTimestamp(l, notification.readAt!))}'
        : '';

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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.body != null && item.body!.isNotEmpty) ...[
                Text(item.body!),
                const SizedBox(height: 4),
              ],
              Text(
                '$receivedStr$readStr',
                style: dimStyle,
              ),
            ],
          ),
          trailing: notification.isRead
              ? null
              : Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}
