// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';

class FavoritesService extends ChangeNotifier {
  FavoritesService({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
    String namespace = '',
  }) : _memory = memory ?? <String, Object?>{},
       _store = store,
       _legacyFavoritesKey = namespace.isEmpty
           ? 'm3ue_favorites'
           : 'm3ue_favorites_$namespace',
       _favoritesKey = namespace.isEmpty
           ? 'm3ue_favorites'
           : 'm3ue_favorites_$namespace';

  final String _legacyFavoritesKey;
  String? _favoritesKey;
  static const _lastCategoryKey = 'm3ue_last_category';
  static const _lastViewModeKey = 'm3ue_last_view_mode';

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;

  void clearNamespace() {
    if (_favoritesKey == null) return;
    _favoritesKey = null;
    notifyListeners();
  }

  Future<void> selectNamespace(String namespace) async {
    final nextKey = '${_legacyFavoritesKey}_scope_$namespace';
    final changed = _favoritesKey != nextKey;
    _favoritesKey = nextKey;

    final migrationKey = '${_legacyFavoritesKey}_scope_migrated';
    if (await _read(migrationKey) != true) {
      final legacyIds = await _all(_legacyFavoritesKey);
      if (legacyIds.isNotEmpty) {
        final scopedIds = await _all(nextKey)
          ..addAll(legacyIds);
        await _write(nextKey, scopedIds.toList()..sort());
      }
      await _write(migrationKey, true);
    }

    if (changed) notifyListeners();
  }

  Future<bool> add(int streamId) async {
    final key = _favoritesKey;
    if (key == null) return false;
    final ids = await _all(key);
    ids.add(streamId);
    await _write(key, ids.toList()..sort());
    notifyListeners();
    return true;
  }

  Future<bool> remove(int streamId) async {
    final key = _favoritesKey;
    if (key == null) return false;
    final ids = await _all(key);
    ids.remove(streamId);
    await _write(key, ids.toList()..sort());
    notifyListeners();
    return false;
  }

  Future<bool> toggle(int streamId) async =>
      await isFavorite(streamId) ? remove(streamId) : add(streamId);

  Future<bool> isFavorite(int streamId) async =>
      (await all()).contains(streamId);

  Future<Set<int>> all() async {
    final key = _favoritesKey;
    return key == null ? <int>{} : _all(key);
  }

  Future<Set<int>> _all(String key) async {
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
}
