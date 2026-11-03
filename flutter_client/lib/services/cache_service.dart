// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// What a user-triggered "Clear & Refresh" resets.
enum CacheClearScope {
  /// Catalog lists, guide data and artwork.
  all,

  /// Live/VOD/series catalog lists (and DVR/request state) only.
  content,

  /// Guide data only: every channel is re-fetched while the current guide
  /// stays on screen.
  epg,

  /// The on-disk artwork cache only.
  images,
}

class CacheEntry<T> {
  const CacheEntry({required this.data, required this.isStale});

  final T data;
  final bool isStale;
}

/// The small shared keys (`sourceType`), for rolling back a failed switch.
/// Everything else needs no snapshot: each playlist's is kept under its own
/// source key, so loading another never touches the shown one's.
class CacheSnapshot {
  const CacheSnapshot._(this._memory, this._persisted);

  final Map<String, Object?> _memory;
  final Map<String, Object?> _persisted;
}

/// Layered cache for the source catalog.
///
/// The small shared scalar keys (`sourceType`) live in memory + the
/// [PersistentJsonStore] blob. The catalog keys (`liveStreams` / `vodStreams`
/// / `seriesStreams`, the three `*Categories` keys, `epgGuide` and `viewers`)
/// are always backed by the SQLite [CatalogRepository]: reads hit the
/// database (no full-list copy held here) and writes swap the relevant rows,
/// so a cold start never parses a multi-MB JSON blob and a catalog refresh
/// never re-serializes one. Each saved playlist's are kept apart under its
/// own source key: reads and writes are the [CatalogRepository.shownSource]'s
/// unless they name another.
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

  /// The SQLite catalog the large keys are stored in.
  CatalogRepository get catalogRepository => _repo;

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
  static const String _viewersKey = 'viewers';

  bool _isRepoKey(String key) =>
      _itemKinds.containsKey(key) ||
      _categoryKinds.containsKey(key) ||
      key == _epgKey ||
      key == _viewersKey;

  /// [sourceKey]'s key/value slot called [name]. The default source keeps
  /// the unprefixed names slots had before each playlist had its own.
  static String _sourceSlot(String name, String sourceKey) =>
      sourceKey == CatalogRepository.defaultSource ? name : '$sourceKey/$name';

  /// The marker row for [key]: [sourceKey]'s, written with its rows.
  static String _tsKey(String key, String sourceKey) =>
      _sourceSlot('__ts_$key', sourceKey);

  /// Every key/value slot kept per source (see [catalogKeys]).
  static List<String> _sourceSlots(String sourceKey) => [
    for (final key in catalogKeys) _tsKey(key, sourceKey),
    _sourceSlot(_viewersKey, sourceKey),
  ];

  Future<void> set<T>(String key, T data) async {
    if (_isRepoKey(key)) {
      await _writeRepoKey(key, data, DateTime.now(), _repo.shownSource);
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

  /// [key]'s entry: the shown playlist's for a catalog key, unless
  /// [sourceKey] names another.
  Future<CacheEntry<T>?> get<T>(String key, {String? sourceKey}) async {
    if (_isRepoKey(key)) {
      return _readRepoKey<T>(key, sourceKey ?? _repo.shownSource);
    }

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

  /// How many rows a catalog item key (`liveStreams` / `vodStreams` /
  /// `seriesStreams`) holds for the shown playlist (or [sourceKey]'s), or null
  /// when it has never been written. Lets a caller check for cached content
  /// without decoding every row.
  Future<int?> itemCount(String key, {String? sourceKey}) async {
    final kind = _itemKinds[key];
    if (kind == null) throw ArgumentError.value(key, 'key', 'not an item key');
    final repo = _repo;
    final source = sourceKey ?? repo.shownSource;
    if (repo.isClosed || await repo.kvUpdatedAt(_tsKey(key, source)) == null) {
      return null;
    }
    return repo.countItems(sourceKey: source, kind: kind);
  }

  Future<CacheSnapshot> snapshot() async {
    final memory = Map<String, Object?>.fromEntries(
      _memory.entries.where((entry) => entry.key.startsWith('m3ue_cache_')),
    );
    final persisted = Map<String, Object?>.from(
      await _store?.snapshot() ?? const <String, Object?>{},
    )..removeWhere((key, _) => !key.startsWith('m3ue_cache_'));
    return CacheSnapshot._(memory, persisted);
  }

  /// A [replace] value meaning "leave this key's stored data as it is"
  /// (rather than wiping it, as [replace] does to keys it isn't given). Used
  /// for the guide, which `EpgService` writes through on its own.
  static const Object keepExisting = _KeepExisting();

  /// Writes [values], wiping every cache key it leaves out. The catalog keys
  /// go under [sourceKey] (the shown playlist when null), leaving every other
  /// playlist's as they are.
  Future<void> replace(Map<String, Object?> values, {String? sourceKey}) async {
    final source = sourceKey ?? _repo.shownSource;
    final timestamp = DateTime.now();
    final memory = <String, Object?>{};
    final persisted = <String, Object?>{};
    for (final entry in values.entries) {
      if (identical(entry.value, keepExisting)) continue;
      if (_isRepoKey(entry.key)) {
        await _writeRepoKey(entry.key, entry.value, timestamp, source);
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
    for (final key in [...catalogKeys, _viewersKey]) {
      if (!values.containsKey(key)) await _clearRepoKey(key, source);
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
    _memory
      ..removeWhere((key, _) => key.startsWith('m3ue_cache_'))
      ..addAll(snapshot._memory);
  }

  /// Wipes everything: every playlist's lists, the guide and the small keys.
  Future<void> clear() async {
    _memory.removeWhere((key, _) => key.startsWith('m3ue_cache_'));
    await _store?.removeWhere((key) => key.startsWith('m3ue_cache_'));
    await _repo.clearAll();
  }

  /// Wipes the small shared keys, keeping what each playlist stored.
  Future<void> clearShared() async {
    _memory.removeWhere((key, _) => key.startsWith('m3ue_cache_'));
    await _store?.removeWhere((key) => key.startsWith('m3ue_cache_'));
  }

  /// Every source key with lists or a guide stored.
  Future<Set<String>> storedCatalogSources() async =>
      _repo.isClosed ? const <String>{} : _repo.storedSources();

  /// Drops everything stored for [sourceKey]: lists, guide and viewers.
  Future<void> dropCatalog(String sourceKey) async {
    final repo = _repo;
    if (repo.isClosed) return;
    await repo.deleteSource(sourceKey);
    for (final slot in _sourceSlots(sourceKey)) {
      await repo.kvDelete(slot);
    }
  }

  /// Moves everything kept under [from] (with when it was written) to [to],
  /// replacing whatever [to] had. A cheap no-op when [from] has no lists.
  Future<void> moveCatalog(String from, String to) async {
    final repo = _repo;
    if (repo.isClosed || from == to) return;
    if (await repo.kvUpdatedAt(_tsKey('liveStreams', from)) == null) return;
    final toSlots = _sourceSlots(to);
    await repo.moveSource(
      from,
      to,
      renameKeys: {
        for (final (index, slot) in _sourceSlots(from).indexed)
          slot: toSlots[index],
      },
    );
  }

  /// Gives [sourceKey] the viewers list stored before each playlist had its
  /// own (the then shown playlist's), unless it has one already.
  Future<void> adoptSharedViewers(String sourceKey) async {
    const legacyKey = 'm3ue_cache_$_viewersKey';
    final legacy = _decodeStampedValue<List<Viewer>>(
      _viewersKey,
      await _store?.read(legacyKey),
    );
    if (legacy == null) return;
    final repo = _repo;
    if (!repo.isClosed &&
        await repo.kvUpdatedAt(_sourceSlot(_viewersKey, sourceKey)) == null) {
      await _writeRepoKey(
        _viewersKey,
        legacy.data,
        legacy.timestamp,
        sourceKey,
      );
    }
    _memory.remove(legacyKey);
    await _store?.removeWhere((key) => key == legacyKey);
  }

  /// When [sourceKey]'s lists were last written, or null if never.
  Future<DateTime?> catalogUpdatedAt(String sourceKey) async {
    if (_repo.isClosed) return null;
    final writtenMs = await _repo.kvUpdatedAt(_tsKey('liveStreams', sourceKey));
    return writtenMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(writtenMs);
  }

  /// The cache keys backed by the SQLite [CatalogRepository] rather than the
  /// JSON store. `main` uses this to purge only the pre-SQLite catalog blobs
  /// from the legacy JSON stores, without touching the scalar keys
  /// (`sourceType`) that still legitimately live there.
  static List<String> get catalogKeys => <String>[
    ..._itemKinds.keys,
    ..._categoryKinds.keys,
    _epgKey,
  ];

  Future<void> _writeRepoKey(
    String key,
    Object? data,
    DateTime timestamp,
    String sourceKey,
  ) async {
    final repo = _repo;
    // A debounced catalog/EPG persist can land after the owning controller was
    // disposed and closed the database; drop it rather than throw.
    if (repo.isClosed) return;
    if (key == _viewersKey) {
      final viewers = (data as List?)?.cast<Viewer>() ?? const <Viewer>[];
      await repo.kvPut(
        _sourceSlot(_viewersKey, sourceKey),
        jsonEncode([for (final viewer in viewers) viewer.toJson()]),
        updatedAtMs: timestamp.millisecondsSinceEpoch,
      );
      return;
    }
    final itemKind = _itemKinds[key];
    if (itemKind != null) {
      await repo.replaceItems(
        sourceKey: sourceKey,
        kind: itemKind,
        items: (data as List?)?.cast<Object>() ?? const <Object>[],
      );
    } else if (_categoryKinds.containsKey(key)) {
      await repo.replaceCategories(
        sourceKey: sourceKey,
        kind: _categoryKinds[key]!,
        categories: (data as List?)?.cast<Category>() ?? const <Category>[],
      );
    } else {
      await repo.replaceProgrammes(
        (data as List?)?.cast<EpgProgram>() ?? const <EpgProgram>[],
        sourceKey: sourceKey,
      );
    }
    // One marker row per catalog key: its presence means "cached", and its
    // `updatedAtMs` (read back via kvUpdatedAt) is the write time the staleness
    // check in _readRepoKey uses. The value column is unused for these rows.
    await repo.kvPut(
      _tsKey(key, sourceKey),
      '',
      updatedAtMs: timestamp.millisecondsSinceEpoch,
    );
  }

  Future<void> _clearRepoKey(String key, String sourceKey) async {
    final repo = _repo;
    if (repo.isClosed) return;
    if (key == _viewersKey) {
      await repo.kvDelete(_sourceSlot(_viewersKey, sourceKey));
      return;
    }
    if (_itemKinds.containsKey(key)) {
      await repo.replaceItems(
        sourceKey: sourceKey,
        kind: _itemKinds[key]!,
        items: const <Object>[],
      );
    } else if (_categoryKinds.containsKey(key)) {
      await repo.replaceCategories(
        sourceKey: sourceKey,
        kind: _categoryKinds[key]!,
        categories: const <Category>[],
      );
    } else {
      await repo.replaceProgrammes(
        const <EpgProgram>[],
        sourceKey: sourceKey,
      );
    }
    await repo.kvDelete(_tsKey(key, sourceKey));
  }

  Future<CacheEntry<T>?> _readRepoKey<T>(String key, String source) async {
    final repo = _repo;
    if (repo.isClosed) return null;
    if (key == _viewersKey) return _readViewers<T>(source);
    final writtenMs = await repo.kvUpdatedAt(_tsKey(key, source));
    if (writtenMs == null) return null;

    final Object data;
    final itemKind = _itemKinds[key];
    if (itemKind != null) {
      data = switch (itemKind) {
        kCatalogKindLive => await repo.allItems<Channel>(source, itemKind),
        kCatalogKindVod => await repo.allItems<VodItem>(source, itemKind),
        _ => await repo.allItems<Series>(source, itemKind),
      };
    } else if (_categoryKinds.containsKey(key)) {
      data = await repo.allCategories(source, _categoryKinds[key]!);
    } else {
      data = await repo.programmesEndingAfter(
        DateTime.fromMillisecondsSinceEpoch(0),
        sourceKey: source,
      );
    }

    return CacheEntry<T>(data: data as T, isStale: _isStale(writtenMs));
  }

  Future<CacheEntry<T>?> _readViewers<T>(String source) async {
    final slot = _sourceSlot(_viewersKey, source);
    final raw = await _repo.kvGet(slot);
    final writtenMs = await _repo.kvUpdatedAt(slot);
    if (raw == null || writtenMs == null) return null;
    final List<Viewer> viewers;
    try {
      viewers = (jsonDecode(raw) as List)
          .map((item) => Viewer.fromJson(asMap(item)))
          .toList(growable: false);
    } on Object {
      return null;
    }
    return CacheEntry<T>(data: viewers as T, isStale: _isStale(writtenMs));
  }

  bool _isStale(int writtenMs) =>
      DateTime.now().millisecondsSinceEpoch - writtenMs >
      refreshInterval.inMilliseconds;
}

class _StampedValue<T> {
  const _StampedValue(this.data, this.timestamp);

  final T data;
  final DateTime timestamp;
}

// Only the small shared keys reach the JSON store now (`sourceType`); the
// catalog keys are owned by the SQLite [CatalogRepository]. The viewers list
// is still decoded here to adopt one stored before each playlist kept its own.
Object? _encodeCacheData(String key, Object? data) {
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

class _KeepExisting {
  const _KeepExisting();
}
