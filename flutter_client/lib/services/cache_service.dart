// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
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
  final CatalogSnapshot? _catalog;
}

/// Layered cache for the source catalog.
///
/// Small scalar/`Viewer` keys still live in memory + the [PersistentJsonStore]
/// blob. When a [CatalogRepository] is supplied, the large catalog keys
/// (`liveStreams` / `vodStreams` / `seriesStreams`, the three `*Categories`
/// keys, and `epgGuide`) are backed by SQLite instead: reads hit the database
/// (no full-list copy held here) and writes swap the relevant rows, so a cold
/// start no longer parses a multi-MB JSON blob and a catalog refresh no longer
/// re-serializes one.
class CacheService {
  CacheService({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
    CatalogRepository? catalogRepository,
    this.refreshInterval = const Duration(hours: 1),
  }) : _memory = memory ?? <String, Object?>{},
       _store = store,
       _repo = catalogRepository;

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;
  final CatalogRepository? _repo;
  Duration refreshInterval;

  /// Single active source. The `sourceKey` column exists to let a future
  /// multi-source setup share one database; today a source switch swaps every
  /// row wholesale so one fixed key is enough.
  static const String _sourceKey = 'active';

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
      _repo != null &&
      (_itemKinds.containsKey(key) ||
          _categoryKinds.containsKey(key) ||
          key == _epgKey);

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
    return CacheSnapshot._(memory, persisted, await _repo?.snapshot());
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
    if (_repo != null) {
      for (final key in _repoKeys) {
        if (!values.containsKey(key)) await _clearRepoKey(key);
      }
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
    final catalog = snapshot._catalog;
    if (_repo != null && catalog != null) await _repo.restore(catalog);
    _memory
      ..removeWhere((key, _) => key.startsWith('m3ue_cache_'))
      ..addAll(snapshot._memory);
  }

  Future<void> clear() async {
    _memory.removeWhere((key, _) => key.startsWith('m3ue_cache_'));
    await _store?.removeWhere((key) => key.startsWith('m3ue_cache_'));
    await _repo?.clearAll();
  }

  static Iterable<String> get _repoKeys => <String>[
    ..._itemKinds.keys,
    ..._categoryKinds.keys,
    _epgKey,
  ];

  Future<void> _writeRepoKey(
    String key,
    Object? data,
    DateTime timestamp,
  ) async {
    final repo = _repo!;
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
    await repo.kvPut(_tsKey(key), timestamp.millisecondsSinceEpoch.toString());
  }

  Future<void> _clearRepoKey(String key) async {
    final repo = _repo!;
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
    final repo = _repo!;
    final rawTs = await repo.kvGet(_tsKey(key));
    if (rawTs == null) return null;
    final writtenMs = int.tryParse(rawTs);
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

Object? _encodeCacheData(String key, Object? data) {
  if (data is List<Category>) {
    return data.map(encodeCategory).toList(growable: false);
  }
  if (data is List<Channel>) {
    return data.map(encodeChannel).toList(growable: false);
  }
  if (data is List<VodItem>) {
    return data.map(encodeVod).toList(growable: false);
  }
  if (data is List<Series>) {
    return data.map(encodeSeries).toList(growable: false);
  }
  if (data is List<EpgProgram>) {
    return data.map(encodeEpgProgram).toList(growable: false);
  }
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
    'liveCategories' || 'vodCategories' || 'seriesCategories' =>
      list?.map((item) => decodeCategory(asMap(item))).toList(growable: false),
    'liveStreams' =>
      list?.map((item) => decodeChannel(asMap(item))).toList(growable: false),
    'vodStreams' =>
      list?.map((item) => decodeVod(asMap(item))).toList(growable: false),
    'seriesStreams' =>
      list?.map((item) => decodeSeries(asMap(item))).toList(growable: false),
    'viewers' =>
      list?.map((item) => Viewer.fromJson(asMap(item))).toList(growable: false),
    'epgGuide' =>
      list
          ?.map((item) => decodeEpgProgram(asMap(item)))
          .whereType<EpgProgram>()
          .toList(growable: false),
    _ => raw,
  };
}
