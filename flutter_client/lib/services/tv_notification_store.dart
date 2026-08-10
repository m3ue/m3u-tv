// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:m3u_tv/services/async_lifecycle.dart';
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
    'admin_only': item.adminOnly,
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
        adminOnly: map['admin_only'] == true,
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
  final SerialQueue _mutationQueue = SerialQueue();
  String? _ownerKey;

  // In-memory cache so callers don't need to await for a hot-path check.
  Set<String>? _subscribedChannelsCache;
  List<TvNotificationChannel>? _serverChannelsCache;

  bool selectOwner({
    required String server,
    required String accountPrincipal,
    required TvPlaylistSession session,
  }) {
    final ownerKey = _notificationOwnerKey(server, accountPrincipal, session);
    if (ownerKey == null) {
      clearOwner();
      return false;
    }
    if (_ownerKey == ownerKey) return true;
    _ownerKey = ownerKey;
    _subscribedChannelsCache = null;
    _serverChannelsCache = null;
    return true;
  }

  void clearOwner() {
    _ownerKey = null;
    _subscribedChannelsCache = null;
    _serverChannelsCache = null;
  }

  /// True while [owner] is still the current owner and [shouldCommit] (if
  /// given) still agrees the caller may write.
  bool _ownsMutation(String owner, [bool Function()? shouldCommit]) =>
      _ownerKey == owner && (shouldCommit?.call() ?? true);

  /// The set of channel names the user wants to receive. Empty means all.
  Future<Set<String>> subscribedChannels() async {
    final owner = _ownerKey;
    if (owner == null) return <String>{};
    if (_subscribedChannelsCache != null) return _subscribedChannelsCache!;
    final key = _ownedKey(_channelsKey, owner);
    final raw = _store == null ? _memory[key] : await _store.read(key);
    if (_ownerKey != owner) return <String>{};
    if (raw is List) {
      _subscribedChannelsCache = raw.map((e) => '$e').toSet();
    } else {
      _subscribedChannelsCache = <String>{};
    }
    return _subscribedChannelsCache!;
  }

  Future<void> setSubscribedChannels(Set<String> channels) => _mutate(() async {
    final owner = _ownerKey;
    if (owner == null) return;
    bool ownsMutation() => _ownsMutation(owner);
    final encoded = channels.toList(growable: false);
    final key = _ownedKey(_channelsKey, owner);
    final store = _store;
    if (store != null && !await store.writeIf(key, encoded, ownsMutation)) {
      return;
    }
    if (!ownsMutation()) return;
    _subscribedChannelsCache = Set.unmodifiable(channels);
    _memory[key] = encoded;
  });

  /// Channels configured in the editor and delivered via the API on connect.
  Future<List<TvNotificationChannel>> serverChannels() async {
    final owner = _ownerKey;
    if (owner == null) return const <TvNotificationChannel>[];
    if (_serverChannelsCache != null) return _serverChannelsCache!;
    final key = _ownedKey(_serverChannelsKey, owner);
    final raw = _store == null ? _memory[key] : await _store.read(key);
    if (_ownerKey != owner) return const <TvNotificationChannel>[];
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

  Future<void> setServerChannels(
    List<TvNotificationChannel> channels, {
    bool Function()? shouldCommit,
  }) async {
    final owner = _ownerKey;
    if (owner == null) return;
    bool ownsMutation() => _ownsMutation(owner, shouldCommit);
    final encoded = channels
        .map((c) => {'name': c.name, 'label': c.label})
        .toList(growable: false);
    if (!ownsMutation()) return;
    final key = _ownedKey(_serverChannelsKey, owner);
    final store = _store;
    if (store != null && !await store.writeIf(key, encoded, ownsMutation)) {
      return;
    }
    if (!ownsMutation()) return;
    _serverChannelsCache = List.unmodifiable(channels);
    _memory[key] = encoded;
  }

  /// Returns all stored notifications, most recent first.
  /// Pass [channelFilter] to restrict to specific channels (empty = all).
  Future<List<StoredTvNotification>> all({Set<String>? channelFilter}) {
    final owner = _ownerKey;
    if (owner == null) {
      return Future.value(const <StoredTvNotification>[]);
    }
    return _allFor(owner, channelFilter: channelFilter);
  }

  Future<List<StoredTvNotification>> _allFor(
    String owner, {
    Set<String>? channelFilter,
  }) async {
    final raw = await _read(owner);
    if (_ownerKey != owner) return const <StoredTvNotification>[];
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
    final owner = _ownerKey;
    if (owner == null) return const <TvNotificationChannel>[];
    final server = await serverChannels();
    if (_ownerKey != owner) return const <TvNotificationChannel>[];
    final serverNames = server.map((c) => c.name).toSet();

    final notifications = await _allFor(owner);
    if (_ownerKey != owner) return const <TvNotificationChannel>[];
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
    List<TvNotificationItem> serverUnread, {
    bool Function()? shouldCommit,
  }) => _mutate(() async {
    final owner = _ownerKey;
    if (owner == null) return const <TvNotificationItem>[];
    bool ownsMutation() => _ownsMutation(owner, shouldCommit);
    if (!ownsMutation()) {
      return const <TvNotificationItem>[];
    }
    final serverUnreadIds = {for (final n in serverUnread) n.id};
    final existing = await _allFor(owner);
    if (!ownsMutation()) {
      return const <TvNotificationItem>[];
    }
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

    final committed = await _write(
      owner,
      [...newItems, ...kept].take(_maxStored).toList(growable: false),
      shouldCommit: ownsMutation,
    );
    if (!committed || !ownsMutation()) {
      return const <TvNotificationItem>[];
    }
    return newItems.map((n) => n.item).toList(growable: false);
  });

  /// Adds a newly received notification as unread. No-op if its id is
  /// already stored (e.g. delivered via both the unread-fetch and Reverb push).
  Future<bool> add(
    TvNotificationItem item, {
    bool Function()? shouldCommit,
  }) => _mutate(() async {
    final owner = _ownerKey;
    if (owner == null) return false;
    bool ownsMutation() => _ownsMutation(owner, shouldCommit);
    if (!ownsMutation()) return false;
    final existing = await _allFor(owner);
    if (!ownsMutation()) return false;
    if (existing.any((n) => n.item.id == item.id)) return false;
    final updated = [
      StoredTvNotification(
        item: item,
        receivedAt: DateTime.now(),
        isRead: false,
      ),
      ...existing,
    ];
    return _write(
      owner,
      updated.take(_maxStored).toList(growable: false),
      shouldCommit: ownsMutation,
    );
  });

  Future<void> markRead(String id) => _markRead(id);

  Future<void> markReadIf(String id, bool Function() shouldCommit) =>
      _markRead(id, shouldCommit: shouldCommit);

  Future<void> _markRead(
    String id, {
    bool Function()? shouldCommit,
  }) => _mutate(() async {
    final owner = _ownerKey;
    if (owner == null) return;
    bool ownsMutation() => _ownsMutation(owner, shouldCommit);
    if (!ownsMutation()) return;
    final existing = await _allFor(owner);
    if (!ownsMutation()) return;
    var changed = false;
    final now = DateTime.now();
    final updated = existing
        .map((n) {
          if (n.item.id != id || n.isRead) return n;
          changed = true;
          return n.copyWith(isRead: true, readAt: now);
        })
        .toList(growable: false);
    if (changed) await _write(owner, updated, shouldCommit: ownsMutation);
  });

  Future<void> markAllRead() => _markAllRead();

  Future<void> markAllReadIf(bool Function() shouldCommit) =>
      _markAllRead(shouldCommit: shouldCommit);

  Future<void> _markAllRead({bool Function()? shouldCommit}) =>
      _mutate(() async {
        final owner = _ownerKey;
        if (owner == null) return;
        bool ownsMutation() => _ownsMutation(owner, shouldCommit);
        if (!ownsMutation()) return;
        final existing = await _allFor(owner);
        if (!ownsMutation()) return;
        if (existing.every((n) => n.isRead)) return;
        final now = DateTime.now();
        await _write(
          owner,
          existing
              .map((n) => n.isRead ? n : n.copyWith(isRead: true, readAt: now))
              .toList(growable: false),
          shouldCommit: ownsMutation,
        );
      });

  Future<Object?> _read(String owner) async {
    final key = _ownedKey(_key, owner);
    return _store == null ? _memory[key] : _store.read(key);
  }

  Future<bool> _write(
    String owner,
    List<StoredTvNotification> notifications, {
    bool Function()? shouldCommit,
  }) async {
    bool ownsMutation() => _ownsMutation(owner, shouldCommit);
    if (!ownsMutation()) return false;
    final encoded = notifications.map((n) => n.toJson()).toList();
    final key = _ownedKey(_key, owner);
    final store = _store;
    if (store != null && !await store.writeIf(key, encoded, ownsMutation)) {
      return false;
    }
    if (!ownsMutation()) return false;
    _memory[key] = encoded;
    return true;
  }

  Future<T> _mutate<T>(Future<T> Function() operation) =>
      _mutationQueue.run(operation);

  static String _ownedKey(String key, String owner) => '${key}_v3_$owner';

  static String? _notificationOwnerKey(
    String server,
    String accountPrincipal,
    TvPlaylistSession session,
  ) {
    final type = session.notifiableType.trim().toLowerCase();
    final uri = Uri.tryParse(server.trim());
    if (session.notifiableId <= 0 ||
        type.isEmpty ||
        accountPrincipal.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty) {
      return null;
    }
    final defaultPort =
        (uri.scheme.toLowerCase() == 'https' && uri.port == 443) ||
        (uri.scheme.toLowerCase() == 'http' && uri.port == 80);
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final source = Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort && !defaultPort ? uri.port : null,
      path: path,
    );
    return sha256
        .convert(
          utf8.encode(
            jsonEncode(<Object>[
              source.toString(),
              type,
              session.notifiableId,
              accountPrincipal,
            ]),
          ),
        )
        .toString();
  }
}
