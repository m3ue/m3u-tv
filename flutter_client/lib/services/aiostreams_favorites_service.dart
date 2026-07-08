import 'package:flutter/foundation.dart';
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

  /// In-memory cache so reads after the first load are synchronous.
  Map<String, AIOStreamsFavoriteItem>? _cache;

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

  Future<void> _persist() async {
    final data = _cache?.map((k, v) => MapEntry(k, v.toJson()));
    await _store?.write(_key, data ?? {});
  }

  Future<bool> isFavorite(String itemId) async =>
      (await _all()).containsKey(itemId);

  Future<void> add(AIOStreamsFavoriteItem item) async {
    final all = await _all();
    all[item.id] = item;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String itemId) async {
    final all = await _all();
    all.remove(itemId);
    await _persist();
    notifyListeners();
  }

  Future<bool> toggle(AIOStreamsFavoriteItem item) async {
    if (await isFavorite(item.id)) {
      await remove(item.id);
      return false;
    } else {
      await add(item);
      return true;
    }
  }

  /// Returns favorites in most-recently-added order (reversed insertion).
  Future<List<AIOStreamsFavoriteItem>> all() async =>
      (await _all()).values.toList().reversed.toList(growable: false);
}
