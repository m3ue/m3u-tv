// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

export 'package:m3u_tv/services/tv_notification_service.dart'
    show TvNotificationChannel;

/// A [TvNotificationItem] plus local read state and receipt time.
class StoredTvNotification {
  const StoredTvNotification({
    required this.item,
    required this.receivedAt,
    required this.isRead,
    this.readAt,
  });

  final TvNotificationItem item;
  final DateTime receivedAt;
  final bool isRead;
  final DateTime? readAt;

  StoredTvNotification copyWith({bool? isRead, DateTime? readAt}) =>
      StoredTvNotification(
        item: item,
        receivedAt: receivedAt,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': item.id,
    'channel': item.channel,
    'title': item.title,
    'body': item.body,
    'status': item.status,
    'received_at': receivedAt.toIso8601String(),
    'is_read': isRead,
    'read_at': readAt?.toIso8601String(),
  };

  static StoredTvNotification? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, Object?>();
    final receivedAt = DateTime.tryParse('${map['received_at']}');
    if (receivedAt == null) return null;
    return StoredTvNotification(
      item: TvNotificationItem(
        id: '${map['id'] ?? ''}',
        channel: '${map['channel'] ?? 'general'}',
        title: '${map['title'] ?? ''}',
        body: map['body'] as String?,
        status: '${map['status'] ?? 'info'}',
      ),
      receivedAt: receivedAt,
      isRead: map['is_read'] == true,
      readAt: map['read_at'] != null
          ? DateTime.tryParse('${map['read_at']}')
          : null,
    );
  }
}

/// Local persistence for TV notification read/unread state, keyed by
/// [TvNotificationItem.id]. The server is the source of truth for content;
/// this store only tracks whether the user has seen each item locally so the
/// notifications list survives app restarts.
///
/// Also persists the user's channel subscription filter — an empty set means
/// "receive all channels"; a non-empty set means only those channels are
/// counted toward the unread badge and surfaced in the notification stream.
/// All notifications are stored regardless of the filter so the user can
/// revisit them if they change their subscription later.
class TvNotificationStore {
  TvNotificationStore({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
  }) : _memory = memory ?? <String, Object?>{},
       _store = store;

  static const _key = 'm3ue_tv_notifications';
  static const _channelsKey = 'm3ue_tv_notification_channels';
  static const _serverChannelsKey = 'm3ue_tv_server_channels';
  static const _maxStored = 100;

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;

  // In-memory cache so callers don't need to await for a hot-path check.
  Set<String>? _subscribedChannelsCache;
  List<TvNotificationChannel>? _serverChannelsCache;

  /// The set of channel names the user wants to receive. Empty means all.
  Future<Set<String>> subscribedChannels() async {
    if (_subscribedChannelsCache != null) return _subscribedChannelsCache!;
    final raw = _store == null
        ? _memory[_channelsKey]
        : await _store.read(_channelsKey);
    if (raw is List) {
      _subscribedChannelsCache = raw.map((e) => '$e').toSet();
    } else {
      _subscribedChannelsCache = <String>{};
    }
    return _subscribedChannelsCache!;
  }

  Future<void> setSubscribedChannels(Set<String> channels) async {
    _subscribedChannelsCache = Set.unmodifiable(channels);
    final encoded = channels.toList(growable: false);
    _memory[_channelsKey] = encoded;
    await _store?.write(_channelsKey, encoded);
  }

  /// Channels configured in the editor and delivered via the API on connect.
  Future<List<TvNotificationChannel>> serverChannels() async {
    if (_serverChannelsCache != null) return _serverChannelsCache!;
    final raw = _store == null
        ? _memory[_serverChannelsKey]
        : await _store.read(_serverChannelsKey);
    if (raw is List) {
      _serverChannelsCache = raw
          .whereType<Map<String, Object?>>()
          .map(TvNotificationChannel.fromJson)
          .where((c) => c.name.isNotEmpty)
          .toList(growable: false);
    } else {
      _serverChannelsCache = const [];
    }
    return _serverChannelsCache!;
  }

  Future<void> setServerChannels(List<TvNotificationChannel> channels) async {
    _serverChannelsCache = List.unmodifiable(channels);
    final encoded = channels
        .map((c) => {'name': c.name, 'label': c.label})
        .toList(growable: false);
    _memory[_serverChannelsKey] = encoded;
    await _store?.write(_serverChannelsKey, encoded);
  }

  /// Returns all stored notifications, most recent first.
  /// Pass [channelFilter] to restrict to specific channels (empty = all).
  Future<List<StoredTvNotification>> all({Set<String>? channelFilter}) async {
    final raw = await _read();
    if (raw is! List) return const <StoredTvNotification>[];
    final notifications = raw
        .map(StoredTvNotification.fromJson)
        .whereType<StoredTvNotification>();
    if (channelFilter != null && channelFilter.isNotEmpty) {
      return notifications
          .where((n) => channelFilter.contains(n.item.channel))
          .toList(growable: false);
    }
    return notifications.toList(growable: false);
  }

  /// All known channels: server-configured ones merged with channels seen in
  /// stored notifications. Server channels appear first (preserving editor
  /// order), then any additional channels discovered from notifications.
  Future<List<TvNotificationChannel>> knownChannels() async {
    final server = await serverChannels();
    final serverNames = server.map((c) => c.name).toSet();

    final notifications = await all();
    final fromNotifications =
        notifications
            .map((n) => n.item.channel)
            .where((name) => !serverNames.contains(name))
            .toSet()
            .map((name) => TvNotificationChannel(name: name, label: ''))
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));

    return [...server, ...fromNotifications];
  }

  /// Unread count, optionally restricted to [channelFilter].
  Future<int> unreadCount({Set<String>? channelFilter}) async =>
      (await all(channelFilter: channelFilter)).where((n) => !n.isRead).length;

  /// Replaces the local store with the server's authoritative unread list.
  ///
  /// Any locally stored notification whose ID is absent from [serverUnread]
  /// is removed — the server read, deleted, or pruned it. New items in
  /// [serverUnread] not yet stored locally are prepended as unread. Returns
  /// only the newly added items so callers can decide whether to toast them.
  Future<List<TvNotificationItem>> syncUnreadWithServer(
    List<TvNotificationItem> serverUnread,
  ) async {
    final serverUnreadIds = {for (final n in serverUnread) n.id};
    final existing = await all();
    final existingIds = {for (final n in existing) n.item.id};
    final now = DateTime.now();

    // Drop anything the server no longer has.
    final kept = existing
        .where((n) => serverUnreadIds.contains(n.item.id))
        .toList(growable: false);

    final newItems = serverUnread
        .where((item) => !existingIds.contains(item.id))
        .map(
          (item) => StoredTvNotification(
            item: item,
            receivedAt: now,
            isRead: false,
          ),
        )
        .toList(growable: false);

    await _write(
      [...newItems, ...kept].take(_maxStored).toList(growable: false),
    );
    return newItems.map((n) => n.item).toList(growable: false);
  }

  /// Adds a newly received notification as unread. No-op if its id is
  /// already stored (e.g. delivered via both the unread-fetch and Reverb push).
  Future<void> add(TvNotificationItem item) async {
    final existing = await all();
    if (existing.any((n) => n.item.id == item.id)) return;
    final updated = [
      StoredTvNotification(
        item: item,
        receivedAt: DateTime.now(),
        isRead: false,
      ),
      ...existing,
    ];
    await _write(updated.take(_maxStored).toList(growable: false));
  }

  Future<void> markRead(String id) async {
    final existing = await all();
    var changed = false;
    final now = DateTime.now();
    final updated = existing
        .map((n) {
          if (n.item.id != id || n.isRead) return n;
          changed = true;
          return n.copyWith(isRead: true, readAt: now);
        })
        .toList(growable: false);
    if (changed) await _write(updated);
  }

  Future<void> markAllRead() async {
    final existing = await all();
    if (existing.every((n) => n.isRead)) return;
    final now = DateTime.now();
    await _write(
      existing
          .map((n) => n.isRead ? n : n.copyWith(isRead: true, readAt: now))
          .toList(growable: false),
    );
  }

  Future<Object?> _read() async =>
      _store == null ? _memory[_key] : _store.read(_key);

  Future<void> _write(List<StoredTvNotification> notifications) async {
    final encoded = notifications.map((n) => n.toJson()).toList();
    _memory[_key] = encoded;
    await _store?.write(_key, encoded);
  }
}
