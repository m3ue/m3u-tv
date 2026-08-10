// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/persistent_store.dart';

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

  Future<bool> add(int streamId) {
    final shouldCommit = captureMutationOwnership?.call() ?? () => true;
    return _mutationQueue.run(
      () => _add(streamId, shouldCommit: shouldCommit),
    );
  }

  Future<bool> _add(
    int streamId, {
    required FavoritesMutationOwnership shouldCommit,
  }) async {
    final ids = await all();
    ids.add(streamId);
    if (!await _writeIf(_favoritesKey, ids.toList()..sort(), shouldCommit)) {
      return false;
    }
    if (!shouldCommit()) return false;
    notifyListeners();
    if (shouldCommit()) onChanged?.call(streamId, favorited: true);
    return true;
  }

  Future<bool> remove(int streamId) {
    final shouldCommit = captureMutationOwnership?.call() ?? () => true;
    return _mutationQueue.run(
      () => _remove(streamId, shouldCommit: shouldCommit),
    );
  }

  Future<bool> _remove(
    int streamId, {
    required FavoritesMutationOwnership shouldCommit,
  }) async {
    final ids = await all();
    ids.remove(streamId);
    if (!await _writeIf(_favoritesKey, ids.toList()..sort(), shouldCommit)) {
      return true;
    }
    if (!shouldCommit()) return true;
    notifyListeners();
    if (shouldCommit()) onChanged?.call(streamId, favorited: false);
    return false;
  }

  Future<bool> toggle(int streamId) {
    final shouldCommit = captureMutationOwnership?.call() ?? () => true;
    return _mutationQueue.run(() async {
      if ((await all()).contains(streamId)) {
        return _remove(streamId, shouldCommit: shouldCommit);
      }
      return _add(streamId, shouldCommit: shouldCommit);
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
    return _mutationQueue.run(() async {
      final ids = await all();
      final changed = favorited ? ids.add(streamId) : ids.remove(streamId);
      if (!changed) return;
      if (!await _writeIf(_favoritesKey, ids.toList()..sort(), canCommit)) {
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
  }) {
    final capturedOwnership = captureMutationOwnership?.call();
    final canCommit = _combineOwnership(capturedOwnership, shouldCommit);
    return _mutationQueue.run(() async {
      final value = streamIds.toSet().toList()..sort();
      if (!await _writeIf(_favoritesKey, value, canCommit)) return false;
      if (!canCommit()) return false;
      notifyListeners();
      return true;
    });
  }

  Future<bool> isFavorite(int streamId) async =>
      (await all()).contains(streamId);

  Future<Set<int>> all() async {
    final raw = await _read(_favoritesKey);
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
