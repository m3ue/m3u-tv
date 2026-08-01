import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// Metadata stored per AIOStreams favourite item.
class AIOStreamsFavoriteItem {
  const AIOStreamsFavoriteItem({
    required this.id,
    required this.type,
    required this.name,
    required this.integrationId,
    this.poster,
  });

  factory AIOStreamsFavoriteItem.fromJson(Map<String, Object?> json) =>
      AIOStreamsFavoriteItem(
        id: '${json['id'] ?? ''}',
        type: '${json['type'] ?? ''}',
        name: '${json['name'] ?? ''}',
        integrationId: (json['integrationId'] as num?)?.toInt() ?? 0,
        poster: json['poster'] as String?,
      );

  final String id;
  final String type;
  final String name;
  final int integrationId;
  final String? poster;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'integrationId': integrationId,
    if (poster != null) 'poster': poster,
  };
}

/// Persists AIOStreams favourite items keyed by their string item ID.
/// AIOStreams items are identified by IMDb-style string IDs (e.g. "tt1234567").
class AIOStreamsFavoritesService extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  AIOStreamsFavoritesService({PersistentJsonStore? store}) : _store = store;

  static const _key = 'aio_favorites';

  final PersistentJsonStore? _store;
  final SerialQueue _mutationQueue = SerialQueue();

  /// In-memory cache so reads after the first load are synchronous.
  Map<String, AIOStreamsFavoriteItem>? _cache;

  /// Invoked after [add] persists a new favorite locally, so the app layer
  /// can push it (with its full metadata — the server has no other way to
  /// learn an AIOStreams item's title/poster/type) to a sync backend.
  void Function(AIOStreamsFavoriteItem item)? onAdded;

  /// Invoked after [remove] persists locally, mirroring [onAdded].
  void Function(String itemId)? onRemoved;

  Future<Map<String, AIOStreamsFavoriteItem>> _all() async {
    if (_cache != null) return _cache!;
    final raw = await _store?.read(_key);
    if (raw is Map) {
      _cache = Map.fromEntries(
        raw.entries.map((e) {
          final v = e.value;
          if (v is Map) {
            return MapEntry(
              '${e.key}',
              AIOStreamsFavoriteItem.fromJson(v.cast<String, Object?>()),
            );
          }
          return null;
        }).whereType<MapEntry<String, AIOStreamsFavoriteItem>>(),
      );
    } else {
      _cache = {};
    }
    return _cache!;
  }

  Future<void> _persist(Map<String, AIOStreamsFavoriteItem> cache) async {
    final data = cache.map((key, value) => MapEntry(key, value.toJson()));
    await _store?.write(_key, data);
  }

  Future<bool> isFavorite(String itemId) async =>
      (await _all()).containsKey(itemId);

  Future<void> add(AIOStreamsFavoriteItem item) =>
      _mutationQueue.run(() => _add(item));

  Future<void> _add(AIOStreamsFavoriteItem item) async {
    final cache = Map<String, AIOStreamsFavoriteItem>.of(await _all());
    cache[item.id] = item;
    await _persist(cache);
    _cache = cache;
    notifyListeners();
    onAdded?.call(item);
  }

  Future<void> remove(String itemId) =>
      _mutationQueue.run(() => _remove(itemId));

  Future<void> _remove(String itemId) async {
    final cache = Map<String, AIOStreamsFavoriteItem>.of(
      await _all(),
    )..remove(itemId);
    await _persist(cache);
    _cache = cache;
    notifyListeners();
    onRemoved?.call(itemId);
  }

  Future<bool> toggle(AIOStreamsFavoriteItem item) => _mutationQueue.run(
    () async {
      if ((await _all()).containsKey(item.id)) {
        await _remove(item.id);
        return false;
      } else {
        await _add(item);
        return true;
      }
    },
  );

  /// Applies a favorite/unfavorite pushed from another device (e.g. a Reverb
  /// `favorite.toggled` event) without re-triggering [onAdded]/[onRemoved]. A
  /// remote "favorited" push with no [item] metadata attached is dropped
  /// rather than stored as a bare id — this shouldn't happen in practice
  /// since the server always carries title/poster/type for aiostreams rows.
  Future<void> applyRemote(
    String itemId, {
    required bool favorited,
    AIOStreamsFavoriteItem? item,
  }) => _mutationQueue.run(() async {
    final cache = Map<String, AIOStreamsFavoriteItem>.of(await _all());
    if (favorited) {
      if (item == null) return;
      cache[itemId] = item;
    } else {
      if (cache.remove(itemId) == null) return;
    }
    await _persist(cache);
    _cache = cache;
    notifyListeners();
  });

  /// Overwrites the full local set from the server's authoritative list
  /// (e.g. after `get_favorites` on connect/viewer switch), without
  /// triggering [onAdded]/[onRemoved].
  Future<bool> replaceAll(
    Iterable<AIOStreamsFavoriteItem> items, {
    bool Function()? shouldCommit,
  }) => _mutationQueue.run(() async {
    final cache = {for (final item in items) item.id: item};
    if (shouldCommit == null) {
      await _persist(cache);
      _cache = cache;
    } else {
      final data = cache.map((key, value) => MapEntry(key, value.toJson()));
      final store = _store;
      if (store != null && !await store.writeIf(_key, data, shouldCommit)) {
        return false;
      }
      if (!shouldCommit()) return false;
      _cache = cache;
    }
    notifyListeners();
    return true;
  });

  /// Returns favorites in most-recently-added order (reversed insertion).
  Future<List<AIOStreamsFavoriteItem>> all() async =>
      (await _all()).values.toList().reversed.toList(growable: false);
}
