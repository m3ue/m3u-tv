// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// One-time move of the catalog out of the `cache.json` JSON blobs and into
/// SQLite, run on boot. Idempotent, and modelled on `PersistentJsonStore`'s
/// `adoptKeysFrom`:
///
/// * if the database already holds catalog rows, only the leftover legacy keys
///   are swept (e.g. from a crash between the import and the delete);
/// * otherwise the legacy `m3ue_cache_*` payloads are decoded through the
///   shared `catalog_codec` (same shape both paths use) and written as rows,
///   then removed from the cache store so the multi-MB blob can't linger.
///
/// Returns true when it imported this run.
class CatalogImporter {
  CatalogImporter({
    required CatalogRepository repository,
    required PersistentJsonStore cacheStore,
    required String sourceKey,
  }) : _repository = repository,
       _cacheStore = cacheStore,
       _sourceKey = sourceKey;

  final CatalogRepository _repository;
  final PersistentJsonStore _cacheStore;
  final String _sourceKey;

  static const _itemKeys = <String, String>{
    'm3ue_cache_liveStreams': kCatalogKindLive,
    'm3ue_cache_vodStreams': kCatalogKindVod,
    'm3ue_cache_seriesStreams': kCatalogKindSeries,
  };
  static const _categoryKeys = <String, String>{
    'm3ue_cache_liveCategories': kCatalogKindLive,
    'm3ue_cache_vodCategories': kCatalogKindVod,
    'm3ue_cache_seriesCategories': kCatalogKindSeries,
  };
  static const _epgKey = 'm3ue_cache_epgGuide';

  static final Set<String> _allLegacyKeys = {
    ..._itemKeys.keys,
    ..._categoryKeys.keys,
    _epgKey,
  };

  Future<bool> run() async {
    final snapshot = await _cacheStore.snapshot();
    final present = _allLegacyKeys.where(snapshot.containsKey).toList();
    if (present.isEmpty) return false;

    if (!await _repository.isEmpty()) {
      // Destination already populated by an earlier run; just clear the
      // stragglers.
      await _cacheStore.removeWhere(_allLegacyKeys.contains);
      return false;
    }

    for (final entry in _itemKeys.entries) {
      final rows = _dataList(snapshot[entry.key]);
      if (rows == null) continue;
      await _repository.replaceItems(
        sourceKey: _sourceKey,
        kind: entry.value,
        items: _decodeItems(entry.value, rows),
      );
    }

    for (final entry in _categoryKeys.entries) {
      final rows = _dataList(snapshot[entry.key]);
      if (rows == null) continue;
      await _repository.replaceCategories(
        sourceKey: _sourceKey,
        kind: entry.value,
        categories: rows
            .map((row) => decodeCategory(asMap(row)))
            .toList(growable: false),
      );
    }

    final epgRows = _dataList(snapshot[_epgKey]);
    if (epgRows != null) {
      await _repository.upsertProgrammes(
        epgRows
            .map((row) => decodeEpgProgram(asMap(row)))
            .whereType<EpgProgram>()
            .toList(growable: false),
      );
    }

    await _cacheStore.removeWhere(_allLegacyKeys.contains);
    return true;
  }

  List<Object?>? _dataList(Object? stampedValue) {
    if (stampedValue is! Map) return null;
    final data = stampedValue['data'];
    return data is List ? data : null;
  }

  List<Object> _decodeItems(String kind, List<Object?> rows) {
    return switch (kind) {
      kCatalogKindLive =>
        rows.map((row) => decodeChannel(asMap(row))).toList(growable: false),
      kCatalogKindVod =>
        rows.map((row) => decodeVod(asMap(row))).toList(growable: false),
      kCatalogKindSeries =>
        rows.map((row) => decodeSeries(asMap(row))).toList(growable: false),
      _ => const <Object>[],
    };
  }
}
