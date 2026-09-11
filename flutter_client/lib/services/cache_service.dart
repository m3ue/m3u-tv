// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

class CacheEntry<T> {
  const CacheEntry({required this.data, required this.isStale});

  final T data;
  final bool isStale;
}

class CacheSnapshot {
  const CacheSnapshot._(this._memory, this._persisted, this._catalog);

  final Map<String, Object?> _memory;
  final Map<String, Object?> _persisted;
  final CatalogSnapshot _catalog;
}

/// Layered cache for the source catalog.
///
/// Small scalar/`Viewer` keys live in memory + the [PersistentJsonStore] blob.
/// The large catalog keys (`liveStreams` / `vodStreams` / `seriesStreams`, the
/// three `*Categories` keys, and `epgGuide`) are always backed by the SQLite
/// [CatalogRepository]: reads hit the database (no full-list copy held here)
/// and writes swap the relevant rows, so a cold start never parses a multi-MB
/// JSON blob and a catalog refresh never re-serializes one.
///
/// There is no JSON code path for those keys. Production injects the on-disk
/// repository (and app startup hard-fails if it can't be opened); a caller
/// that omits one - only tests do - gets a private in-memory SQLite database,
/// so the catalog always exercises the exact same code, just unpersisted.
class CacheService {
  CacheService({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
    CatalogRepository? catalogRepository,
    this.refreshInterval = const Duration(hours: 1),
  }) : _memory = memory ?? <String, Object?>{},
       _store = store,
       _repo = catalogRepository ?? CatalogRepository(CatalogDatabase.memory());

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;
  final CatalogRepository _repo;
  Duration refreshInterval;

  static const String _sourceKey = CatalogRepository.activeSource;

  static const Map<String, String> _itemKinds = {
    'liveStreams': kCatalogKindLive,
    'vodStreams': kCatalogKindVod,
    'seriesStreams': kCatalogKindSeries,
  };
  static const Map<String, String> _categoryKinds = {
    'liveCategories': kCatalogKindLive,
    'vodCategories': kCatalogKindVod,
    'seriesCategories': kCatalogKindSeries,
  };
  static const String _epgKey = 'epgGuide';

  bool _isRepoKey(String key) =>
      _itemKinds.containsKey(key) ||
      _categoryKinds.containsKey(key) ||
      key == _epgKey;

  String _tsKey(String key) => '__ts_$key';

  Future<void> set<T>(String key, T data) async {
    if (_isRepoKey(key)) {
      await _writeRepoKey(key, data, DateTime.now());
      return;
    }
    final stamped = _StampedValue<T>(data, DateTime.now());
    _memory['m3ue_cache_$key'] = stamped;
    final encoded = _encodeCacheData(key, data);
    if (encoded != null) {
      await _store?.write('m3ue_cache_$key', <String, Object?>{
        'timestamp': stamped.timestamp.toIso8601String(),
        'data': encoded,
      });
    }
  }

  Future<CacheEntry<T>?> get<T>(String key) async {
    if (_isRepoKey(key)) return _readRepoKey<T>(key);

    var value = _memory['m3ue_cache_$key'];
    if (value is! _StampedValue && _store != null) {
      value = _decodeStampedValue<T>(key, await _store.read('m3ue_cache_$key'));
      if (value != null) _memory['m3ue_cache_$key'] = value;
    }
    if (value is! _StampedValue) return null;
    return CacheEntry<T>(
      data: value.data as T,
      isStale: DateTime.now().difference(value.timestamp) > refreshInterval,
    );
  }

  Future<CacheSnapshot> snapshot() async {
    final memory = Map<String, Object?>.fromEntries(
      _memory.entries.where((entry) => entry.key.startsWith('m3ue_cache_')),
    );
    final persisted = Map<String, Object?>.from(
      await _store?.snapshot() ?? const <String, Object?>{},
    )..removeWhere((key, _) => !key.startsWith('m3ue_cache_'));
    return CacheSnapshot._(memory, persisted, await _repo.snapshot());
  }

  Future<void> replace(Map<String, Object?> values) async {
    final timestamp = DateTime.now();
    final memory = <String, Object?>{};
    final persisted = <String, Object?>{};
    for (final entry in values.entries) {
      if (_isRepoKey(entry.key)) {
        await _writeRepoKey(entry.key, entry.value, timestamp);
        continue;
      }
      final key = 'm3ue_cache_${entry.key}';
      memory[key] = _StampedValue<Object?>(entry.value, timestamp);
      final encoded = _encodeCacheData(entry.key, entry.value);
      if (encoded != null) {
        persisted[key] = <String, Object?>{
          'timestamp': timestamp.toIso8601String(),
          'data': encoded,
        };
      }
    }
    // replace() wipes every cache key not in [values]; mirror that for the
    // repo-backed keys the caller left out.
    for (final key in catalogKeys) {
      if (!values.containsKey(key)) await _clearRepoKey(key);
    }
    await _store?.replaceWhere(
      (key) => key.startsWith('m3ue_cache_'),
      persisted,
    );
    _memory
      ..removeWhere((key, _) => key.startsWith('m3ue_cache_'))
      ..addAll(memory);
  }

  Future<void> restore(CacheSnapshot snapshot) async {
    final store = _store;
    if (store != null) {
      await store.replaceWhere(
        (key) => key.startsWith('m3ue_cache_'),
        snapshot._persisted,
      );
    }
    await _repo.restore(snapshot._catalog);
    _memory
      ..removeWhere((key, _) => key.startsWith('m3ue_cache_'))
      ..addAll(snapshot._memory);
  }

  Future<void> clear() async {
    _memory.removeWhere((key, _) => key.startsWith('m3ue_cache_'));
    await _store?.removeWhere((key) => key.startsWith('m3ue_cache_'));
    await _repo.clearAll();
  }

  /// The cache keys backed by the SQLite [CatalogRepository] rather than the
  /// JSON store. `main` uses this to purge only the pre-SQLite catalog blobs
  /// from the legacy JSON stores, without touching the scalar keys
  /// (`sourceType`, `viewers`) that still legitimately live there.
  static List<String> get catalogKeys => <String>[
    ..._itemKinds.keys,
    ..._categoryKinds.keys,
    _epgKey,
  ];

  Future<void> _writeRepoKey(
    String key,
    Object? data,
    DateTime timestamp,
  ) async {
    final repo = _repo;
    // A debounced catalog/EPG persist can land after the owning controller was
    // disposed and closed the database; drop it rather than throw.
    if (repo.isClosed) return;
    final itemKind = _itemKinds[key];
    if (itemKind != null) {
      await repo.replaceItems(
        sourceKey: _sourceKey,
        kind: itemKind,
        items: (data as List?)?.cast<Object>() ?? const <Object>[],
      );
    } else if (_categoryKinds.containsKey(key)) {
      await repo.replaceCategories(
        sourceKey: _sourceKey,
        kind: _categoryKinds[key]!,
        categories: (data as List?)?.cast<Category>() ?? const <Category>[],
      );
    } else {
      await repo.replaceProgrammes(
        (data as List?)?.cast<EpgProgram>() ?? const <EpgProgram>[],
      );
    }
    // One marker row per catalog key: its presence means "cached", and its
    // `updatedAtMs` (read back via kvUpdatedAt) is the write time the staleness
    // check in _readRepoKey uses. The value column is unused for these rows.
    await repo.kvPut(
      _tsKey(key),
      '',
      updatedAtMs: timestamp.millisecondsSinceEpoch,
    );
  }

  Future<void> _clearRepoKey(String key) async {
    final repo = _repo;
    if (repo.isClosed) return;
    if (_itemKinds.containsKey(key)) {
      await repo.replaceItems(
        sourceKey: _sourceKey,
        kind: _itemKinds[key]!,
        items: const <Object>[],
      );
    } else if (_categoryKinds.containsKey(key)) {
      await repo.replaceCategories(
        sourceKey: _sourceKey,
        kind: _categoryKinds[key]!,
        categories: const <Category>[],
      );
    } else {
      await repo.replaceProgrammes(const <EpgProgram>[]);
    }
    await repo.kvDelete(_tsKey(key));
  }

  Future<CacheEntry<T>?> _readRepoKey<T>(String key) async {
    final repo = _repo;
    if (repo.isClosed) return null;
    final writtenMs = await repo.kvUpdatedAt(_tsKey(key));
    if (writtenMs == null) return null;

    final Object data;
    final itemKind = _itemKinds[key];
    if (itemKind != null) {
      data = switch (itemKind) {
        kCatalogKindLive => await repo.allItems<Channel>(_sourceKey, itemKind),
        kCatalogKindVod => await repo.allItems<VodItem>(_sourceKey, itemKind),
        _ => await repo.allItems<Series>(_sourceKey, itemKind),
      };
    } else if (_categoryKinds.containsKey(key)) {
      data = await repo.allCategories(_sourceKey, _categoryKinds[key]!);
    } else {
      data = await repo.programmesEndingAfter(
        DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    final age = DateTime.now().millisecondsSinceEpoch - writtenMs;
    return CacheEntry<T>(
      data: data as T,
      isStale: age > refreshInterval.inMilliseconds,
    );
  }
}

class _StampedValue<T> {
  const _StampedValue(this.data, this.timestamp);

  final T data;
  final DateTime timestamp;
}

// Only the small non-catalog keys reach the JSON store now (`sourceType`,
// `viewers`); the catalog lists are owned by the SQLite [CatalogRepository].
Object? _encodeCacheData(String key, Object? data) {
  if (data is List<Viewer>) {
    return data.map((viewer) => viewer.toJson()).toList(growable: false);
  }
  if (data is String || data is num || data is bool || data == null) {
    return data;
  }
  return null;
}

_StampedValue<T>? _decodeStampedValue<T>(String key, Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, Object?>();
  final timestampText = json['timestamp'];
  final timestamp = timestampText is String
      ? DateTime.tryParse(timestampText)
      : null;
  if (timestamp == null) return null;
  final data = _decodeCacheData(key, json['data']);
  if (data == null) return null;
  return _StampedValue<T>(data as T, timestamp);
}

Object? _decodeCacheData(String key, Object? raw) {
  final list = raw is List ? raw.cast<Object?>() : null;
  return switch (key) {
    'viewers' =>
      list?.map((item) => Viewer.fromJson(asMap(item))).toList(growable: false),
    _ => raw,
  };
}
