// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/persistent_store.dart';

class FavoritesService {
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

  Future<bool> add(int streamId) async {
    final ids = await all();
    ids.add(streamId);
    await _write(_favoritesKey, ids.toList()..sort());
    return true;
  }

  Future<bool> remove(int streamId) async {
    final ids = await all();
    ids.remove(streamId);
    await _write(_favoritesKey, ids.toList()..sort());
    return false;
  }

  Future<bool> toggle(int streamId) async =>
      await isFavorite(streamId) ? remove(streamId) : add(streamId);

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
}
