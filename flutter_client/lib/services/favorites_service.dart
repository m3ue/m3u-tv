// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';

typedef FavoritesMutationOwnership = bool Function();
typedef FavoritesMutationOwnershipCapture =
    FavoritesMutationOwnership Function();

class FavoritesService extends ChangeNotifier {
  FavoritesService({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
    String namespace = '',
  }) : _memory = memory ?? <String, Object?>{},
       _store = store,
       _favoritesKey = namespace.isEmpty
           ? 'm3ue_favorites'
           : 'm3ue_favorites_$namespace';

  final String _favoritesKey;
  static const _lastCategoryKey = 'm3ue_last_category';
  static const _lastViewModeKey = 'm3ue_last_view_mode';

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;
  final SerialQueue _mutationQueue = SerialQueue();

  /// Invoked after a local add/remove made through [add]/[remove]/[toggle]
  /// succeeds, so the app layer can push the change to a sync backend.
  /// Fire-and-forget from this service's perspective — it does not await or
  /// retry the callback. Not invoked by [replaceAll]/[applyRemote], which
  /// exist specifically to apply server/remote state without echoing it back.
  void Function(int streamId, {required bool favorited})? onChanged;

  FavoritesMutationOwnershipCapture? captureMutationOwnership;

  /// Keeps each saved playlist's favorites apart (see [playlistScopedKey]).
  /// Unset, or resolving to null, uses the unscoped key.
  PlaylistScope? playlistScope;

  /// The key for the active playlist, captured when a mutation is queued so
  /// it can never land in a playlist that became active after it started.
  String get _scopedFavoritesKey =>
      playlistScopedKey(_favoritesKey, playlistScope?.call());

  Future<bool> add(int streamId) {
    final shouldCommit = captureMutationOwnership?.call() ?? () => true;
    final key = _scopedFavoritesKey;
    return _mutationQueue.run(
      () => _add(streamId, key: key, shouldCommit: shouldCommit),
    );
  }

  Future<bool> _add(
    int streamId, {
    required String key,
    required FavoritesMutationOwnership shouldCommit,
  }) async {
    final ids = await _readIds(key);
    ids.add(streamId);
    if (!await _writeIf(key, ids.toList()..sort(), shouldCommit)) {
      return false;
    }
    if (!shouldCommit()) return false;
    notifyListeners();
    if (shouldCommit()) onChanged?.call(streamId, favorited: true);
    return true;
  }

  Future<bool> remove(int streamId) {
    final shouldCommit = captureMutationOwnership?.call() ?? () => true;
    final key = _scopedFavoritesKey;
    return _mutationQueue.run(
      () => _remove(streamId, key: key, shouldCommit: shouldCommit),
    );
  }

  Future<bool> _remove(
    int streamId, {
    required String key,
    required FavoritesMutationOwnership shouldCommit,
  }) async {
    final ids = await _readIds(key);
    ids.remove(streamId);
    if (!await _writeIf(key, ids.toList()..sort(), shouldCommit)) {
      return true;
    }
    if (!shouldCommit()) return true;
    notifyListeners();
    if (shouldCommit()) onChanged?.call(streamId, favorited: false);
    return false;
  }

  Future<bool> toggle(int streamId) {
    final shouldCommit = captureMutationOwnership?.call() ?? () => true;
    final key = _scopedFavoritesKey;
    return _mutationQueue.run(() async {
      if ((await _readIds(key)).contains(streamId)) {
        return _remove(streamId, key: key, shouldCommit: shouldCommit);
      }
      return _add(streamId, key: key, shouldCommit: shouldCommit);
    });
  }

  /// Applies a single favorite/unfavorite pushed from another device (e.g. a
  /// Reverb `favorite.toggled` event) without re-triggering [onChanged].
  Future<void> applyRemote(
    int streamId, {
    required bool favorited,
    FavoritesMutationOwnership? shouldCommit,
  }) {
    final capturedOwnership = captureMutationOwnership?.call();
    final canCommit = _combineOwnership(capturedOwnership, shouldCommit);
    final key = _scopedFavoritesKey;
    return _mutationQueue.run(() async {
      final ids = await _readIds(key);
      final changed = favorited ? ids.add(streamId) : ids.remove(streamId);
      if (!changed) return;
      if (!await _writeIf(key, ids.toList()..sort(), canCommit)) {
        return;
      }
      if (!canCommit()) return;
      notifyListeners();
    });
  }

  /// Overwrites the full local set from the server's authoritative list
  /// (e.g. after `get_favorites` on connect/viewer switch), without
  /// triggering [onChanged].
  Future<bool> replaceAll(
    Iterable<int> streamIds, {
    bool Function()? shouldCommit,
  }) => replaceAllIn(
    playlistScope?.call(),
    streamIds,
    shouldCommit: shouldCommit,
  );

  /// [replaceAll] for the playlist with [scope] rather than the active one:
  /// a switch stages the incoming playlist's favorites before it is shown.
  Future<bool> replaceAllIn(
    String? scope,
    Iterable<int> streamIds, {
    bool Function()? shouldCommit,
  }) {
    final capturedOwnership = captureMutationOwnership?.call();
    final canCommit = _combineOwnership(capturedOwnership, shouldCommit);
    final key = playlistScopedKey(_favoritesKey, scope);
    return _mutationQueue.run(() async {
      final value = streamIds.toSet().toList()..sort();
      if (!await _writeIf(key, value, canCommit)) return false;
      if (!canCommit()) return false;
      notifyListeners();
      return true;
    });
  }

  Future<bool> isFavorite(int streamId) async =>
      (await all()).contains(streamId);

  Future<Set<int>> all() => _readIds(_scopedFavoritesKey);

  /// [all] for the playlist with [scope] rather than the active one.
  Future<Set<int>> allIn(String? scope) =>
      _readIds(playlistScopedKey(_favoritesKey, scope));

  /// Tells listeners the active playlist changed, so the favorites they read
  /// are now another playlist's.
  void notifyPlaylistChanged() => notifyListeners();

  /// Drops the favorites stored for a removed playlist's [scope].
  Future<void> clearPlaylistState(String? scope) =>
      _mutationQueue.run(() async {
        final key = playlistScopedKey(_favoritesKey, scope);
        _memory.remove(key);
        await _store?.delete(key);
      });

  Future<Set<int>> _readIds(String key) async {
    final raw = await _read(key);
    if (raw is Iterable) return raw.map((value) => int.parse('$value')).toSet();
    return <int>{};
  }

  Future<void> setLastCategory(String? categoryId) async {
    await _write(_lastCategoryKey, categoryId);
  }

  Future<String?> getLastCategory() async =>
      await _read(_lastCategoryKey) as String?;

  Future<void> setLastViewMode(String viewMode) async {
    await _write(_lastViewModeKey, viewMode);
  }

  Future<String?> getLastViewMode() async =>
      await _read(_lastViewModeKey) as String?;

  Future<Object?> _read(String key) async =>
      _store == null ? _memory[key] : _store.read(key);

  Future<void> _write(String key, Object? value) async {
    _memory[key] = value;
    await _store?.write(key, value);
  }

  Future<bool> _writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) async {
    final store = _store;
    if (store != null && !await store.writeIf(key, value, shouldCommit)) {
      return false;
    }
    if (!shouldCommit()) return false;
    _memory[key] = value;
    return true;
  }

  FavoritesMutationOwnership _combineOwnership(
    FavoritesMutationOwnership? captured,
    FavoritesMutationOwnership? requested,
  ) => switch ((captured, requested)) {
    (final ownership?, final guard?) => () => ownership() && guard(),
    (final ownership?, null) => ownership,
    (null, final guard?) => guard,
    (null, null) => () => true,
  };
}
