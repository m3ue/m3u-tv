import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';

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

typedef AIOStreamsMutationOwnership = bool Function();
typedef AIOStreamsMutationOwnershipCapture =
    AIOStreamsMutationOwnership Function();

/// Persists AIOStreams favourite items keyed by their string item ID.
/// AIOStreams items are identified by IMDb-style string IDs (e.g. "tt1234567").
class AIOStreamsFavoritesService extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  AIOStreamsFavoritesService({PersistentJsonStore? store}) : _store = store;

  static const _key = 'aio_favorites';

  final PersistentJsonStore? _store;
  final SerialQueue _mutationQueue = SerialQueue();

  /// In-memory cache per playlist scope (see [playlistScopedKey]) so reads
  /// after the first load are synchronous.
  final Map<String?, Map<String, AIOStreamsFavoriteItem>> _caches =
      <String?, Map<String, AIOStreamsFavoriteItem>>{};

  /// Invoked after [add] persists a new favorite locally, so the app layer
  /// can push it (with its full metadata — the server has no other way to
  /// learn an AIOStreams item's title/poster/type) to a sync backend.
  void Function(AIOStreamsFavoriteItem item)? onAdded;

  /// Invoked after [remove] persists locally, mirroring [onAdded].
  void Function(String itemId)? onRemoved;

  AIOStreamsMutationOwnershipCapture? captureMutationOwnership;

  /// Keeps each saved playlist's favorites apart. Unset, or resolving to
  /// null, uses the unscoped key.
  PlaylistScope? playlistScope;

  /// Tells listeners the active playlist changed, so the favorites they read
  /// are now another playlist's.
  void notifyPlaylistChanged() => notifyListeners();

  /// Moves the favorites kept on the unscoped key (a login from before
  /// multiple playlists) to [scope]'s, unless it already has its own.
  Future<void> adoptUnscoped(String scope) => _mutationQueue.run(() async {
    final store = _store;
    if (store == null) {
      final unscoped = _caches.remove(null);
      if (unscoped != null) _caches.putIfAbsent(scope, () => unscoped);
      return;
    }
    final value = await store.read(_key);
    final key = playlistScopedKey(_key, scope);
    if (value != null && await store.read(key) == null) {
      await store.write(key, value);
      _caches.remove(scope);
    }
    _caches.remove(null);
    await store.delete(_key);
  });

  /// Drops the favorites stored for a removed playlist's [scope].
  Future<void> clearPlaylistState(String? scope) =>
      _mutationQueue.run(() async {
        _caches.remove(scope);
        await _store?.delete(playlistScopedKey(_key, scope));
      });

  Future<Map<String, AIOStreamsFavoriteItem>> _all(String? scope) async {
    final cached = _caches[scope];
    if (cached != null) return cached;
    final raw = await _store?.read(playlistScopedKey(_key, scope));
    final Map<String, AIOStreamsFavoriteItem> loaded;
    if (raw is Map) {
      loaded = Map.fromEntries(
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
      loaded = {};
    }
    return _caches[scope] = loaded;
  }

  Future<bool> _persist(
    Map<String, AIOStreamsFavoriteItem> cache, {
    required String? scope,
    AIOStreamsMutationOwnership? shouldCommit,
  }) async {
    final data = cache.map((key, value) => MapEntry(key, value.toJson()));
    final key = playlistScopedKey(_key, scope);
    final store = _store;
    if (shouldCommit == null) {
      await store?.write(key, data);
      return true;
    }
    if (store == null) return shouldCommit();
    return store.writeIf(key, data, shouldCommit);
  }

  Future<bool> isFavorite(String itemId) async =>
      (await _all(playlistScope?.call())).containsKey(itemId);

  Future<bool> add(AIOStreamsFavoriteItem item) {
    final shouldCommit = captureMutationOwnership?.call();
    final scope = playlistScope?.call();
    return _mutationQueue.run(
      () => _add(item, scope: scope, shouldCommit: shouldCommit),
    );
  }

  Future<bool> _add(
    AIOStreamsFavoriteItem item, {
    required String? scope,
    AIOStreamsMutationOwnership? shouldCommit,
  }) async {
    final cache = Map<String, AIOStreamsFavoriteItem>.of(await _all(scope));
    cache[item.id] = item;
    if (!await _persist(cache, scope: scope, shouldCommit: shouldCommit)) {
      return false;
    }
    if (shouldCommit != null && !shouldCommit()) return false;
    _caches[scope] = cache;
    notifyListeners();
    onAdded?.call(item);
    return true;
  }

  Future<bool> remove(String itemId) {
    final shouldCommit = captureMutationOwnership?.call();
    final scope = playlistScope?.call();
    return _mutationQueue.run(
      () => _remove(itemId, scope: scope, shouldCommit: shouldCommit),
    );
  }

  Future<bool> _remove(
    String itemId, {
    required String? scope,
    AIOStreamsMutationOwnership? shouldCommit,
  }) async {
    final cache = Map<String, AIOStreamsFavoriteItem>.of(
      await _all(scope),
    )..remove(itemId);
    if (!await _persist(cache, scope: scope, shouldCommit: shouldCommit)) {
      return false;
    }
    if (shouldCommit != null && !shouldCommit()) return false;
    _caches[scope] = cache;
    notifyListeners();
    onRemoved?.call(itemId);
    return true;
  }

  /// Returns the item's new favorited state, or its unchanged prior state if
  /// the mutation was rejected by [captureMutationOwnership] (e.g. the
  /// viewer/source switched mid-toggle).
  Future<bool> toggle(AIOStreamsFavoriteItem item) {
    final shouldCommit = captureMutationOwnership?.call();
    final scope = playlistScope?.call();
    return _mutationQueue.run(() async {
      final wasFavorite = (await _all(scope)).containsKey(item.id);
      if (wasFavorite) {
        final removed = await _remove(
          item.id,
          scope: scope,
          shouldCommit: shouldCommit,
        );
        return !removed;
      } else {
        return _add(item, scope: scope, shouldCommit: shouldCommit);
      }
    });
  }

  /// Applies a favorite/unfavorite pushed from another device (e.g. a Reverb
  /// `favorite.toggled` event) without re-triggering [onAdded]/[onRemoved]. A
  /// remote "favorited" push with no [item] metadata attached is dropped
  /// rather than stored as a bare id — this shouldn't happen in practice
  /// since the server always carries title/poster/type for aiostreams rows.
  Future<void> applyRemote(
    String itemId, {
    required bool favorited,
    AIOStreamsFavoriteItem? item,
  }) {
    final shouldCommit = captureMutationOwnership?.call();
    final scope = playlistScope?.call();
    return _mutationQueue.run(() async {
      final cache = Map<String, AIOStreamsFavoriteItem>.of(await _all(scope));
      if (favorited) {
        if (item == null) return;
        cache[itemId] = item;
      } else {
        if (cache.remove(itemId) == null) return;
      }
      if (!await _persist(cache, scope: scope, shouldCommit: shouldCommit)) {
        return;
      }
      if (shouldCommit != null && !shouldCommit()) return;
      _caches[scope] = cache;
      notifyListeners();
    });
  }

  /// Overwrites the full local set from the server's authoritative list
  /// (e.g. after `get_favorites` on connect/viewer switch), without
  /// triggering [onAdded]/[onRemoved].
  Future<bool> replaceAll(
    Iterable<AIOStreamsFavoriteItem> items, {
    bool Function()? shouldCommit,
  }) => replaceAllIn(playlistScope?.call(), items, shouldCommit: shouldCommit);

  /// [replaceAll] for the playlist with [scope] rather than the active one:
  /// a switch stages the incoming playlist's favorites before it is shown.
  Future<bool> replaceAllIn(
    String? scope,
    Iterable<AIOStreamsFavoriteItem> items, {
    bool Function()? shouldCommit,
  }) {
    final capturedOwnership = captureMutationOwnership?.call();
    final canCommit = switch ((capturedOwnership, shouldCommit)) {
      (final ownership?, final requested?) => () => ownership() && requested(),
      (final ownership?, null) => ownership,
      (null, final requested?) => requested,
      (null, null) => null,
    };
    return _mutationQueue.run(() async {
      final cache = {for (final item in items) item.id: item};
      if (!await _persist(cache, scope: scope, shouldCommit: canCommit)) {
        return false;
      }
      if (canCommit != null && !canCommit()) return false;
      _caches[scope] = cache;
      notifyListeners();
      return true;
    });
  }

  /// Returns favorites in most-recently-added order (reversed insertion).
  Future<List<AIOStreamsFavoriteItem>> all() => allIn(playlistScope?.call());

  /// [all] for the playlist with [scope] rather than the active one.
  Future<List<AIOStreamsFavoriteItem>> allIn(String? scope) async =>
      (await _all(scope)).values.toList().reversed.toList(growable: false);
}
