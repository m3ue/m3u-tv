// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

/// A [TvNotificationItem] plus local read state and receipt time.
class StoredTvNotification {
  const StoredTvNotification({
    required this.item,
    required this.receivedAt,
    required this.isRead,
  });

  final TvNotificationItem item;
  final DateTime receivedAt;
  final bool isRead;

  StoredTvNotification copyWith({bool? isRead}) => StoredTvNotification(
    item: item,
    receivedAt: receivedAt,
    isRead: isRead ?? this.isRead,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': item.id,
    'channel': item.channel,
    'title': item.title,
    'body': item.body,
    'status': item.status,
    'received_at': receivedAt.toIso8601String(),
    'is_read': isRead,
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
    );
  }
}

/// Local persistence for TV notification read/unread state, keyed by
/// [TvNotificationItem.id]. The server is the source of truth for content;
/// this store only tracks whether the user has seen each item locally so the
/// notifications list survives app restarts.
class TvNotificationStore {
  TvNotificationStore({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
  }) : _memory = memory ?? <String, Object?>{},
       _store = store;

  static const _key = 'm3ue_tv_notifications';
  static const _maxStored = 100;

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;

  /// Most recent first.
  Future<List<StoredTvNotification>> all() async {
    final raw = await _read();
    if (raw is! List) return const <StoredTvNotification>[];
    return raw
        .map(StoredTvNotification.fromJson)
        .whereType<StoredTvNotification>()
        .toList(growable: false);
  }

  Future<int> unreadCount() async =>
      (await all()).where((n) => !n.isRead).length;

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
    final updated = existing.map((n) {
      if (n.item.id != id || n.isRead) return n;
      changed = true;
      return n.copyWith(isRead: true);
    }).toList(growable: false);
    if (changed) await _write(updated);
  }

  Future<void> markAllRead() async {
    final existing = await all();
    if (existing.every((n) => n.isRead)) return;
    await _write(
      existing.map((n) => n.copyWith(isRead: true)).toList(growable: false),
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
