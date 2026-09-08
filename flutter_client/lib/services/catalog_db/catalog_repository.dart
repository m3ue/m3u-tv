import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Domain-facing wrapper over [CatalogDatabase]. Encodes/decodes rows through
/// `catalog_codec`, keeps the promoted columns in sync, and exposes both the
/// full-list reads the app still relies on and the windowed page/count reads
/// the grids will move to.
class CatalogRepository {
  CatalogRepository(this._db);

  final CatalogDatabase _db;
  bool _closed = false;

  CatalogDatabase get database => _db;

  /// True once [close] has run. Callers touching the repository from a
  /// fire-and-forget path (e.g. a debounced EPG persist that can land after the
  /// owning controller is disposed) check this to skip the work instead of
  /// hitting drift's "can't use a closed database" error.
  bool get isClosed => _closed;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
  }

  /// The one `sourceKey` in use today. The column is multi-source-ready but a
  /// source switch swaps every row wholesale, so callers that only ever touch
  /// the live source use the `*Active` helpers below and never see it.
  static const String activeSource = 'active';

  Future<List<T>> pageActiveItems<T>({
    required String kind,
    String? categoryId,
    String? search,
    required int offset,
    required int limit,
  }) => pageItems<T>(
    sourceKey: activeSource,
    kind: kind,
    categoryId: categoryId,
    search: search,
    offset: offset,
    limit: limit,
  );

  Future<int> countActiveItems({
    required String kind,
    String? categoryId,
    String? search,
  }) => countItems(
    sourceKey: activeSource,
    kind: kind,
    categoryId: categoryId,
    search: search,
  );

  // -------------------------------------------------------------------------
  // Catalog items
  // -------------------------------------------------------------------------

  /// Replace every stored row of [kind] for [sourceKey] with [items] (a list
  /// of `Channel` / `VodItem` / `Series`, matching [kind]). Order in [items]
  /// becomes the stored `sortIndex`. Runs in one transaction so a reader never
  /// sees a half-swapped catalog.
  Future<void> replaceItems({
    required String sourceKey,
    required String kind,
    required List<Object> items,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.catalogItems)
            ..where((t) => t.sourceKey.equals(sourceKey) & t.kind.equals(kind)))
          .go();
      // The PK is (sourceKey, kind, streamId). Provider payloads are not
      // guaranteed unique on stream_id - a missing id decodes to 0, and merged
      // / multi-playlist / AIOStreams sources can repeat ids - and
      // insertOrReplace would silently collapse every clash into one row. Give
      // any clashing element a negative, position-derived surrogate id (real
      // provider ids are positive) so every element survives the round trip.
      // Nothing reads a row back by this column; the decoded `.id` comes from
      // the json payload.
      final usedIds = <int>{};
      await _db.batch((batch) {
        for (var i = 0; i < items.length; i++) {
          var row = _rowFor(sourceKey, kind, items[i], i);
          if (row.streamId.value <= 0 || !usedIds.add(row.streamId.value)) {
            final surrogate = -(i + 1);
            usedIds.add(surrogate);
            row = row.copyWith(streamId: Value(surrogate));
          }
          batch.insert(_db.catalogItems, row, mode: InsertMode.insertOrReplace);
        }
      });
    });
  }

  CatalogItemsCompanion _rowFor(
    String sourceKey,
    String kind,
    Object item,
    int sortIndex,
  ) {
    switch (kind) {
      case kCatalogKindLive:
        final channel = item as Channel;
        return CatalogItemsCompanion.insert(
          sourceKey: sourceKey,
          kind: kind,
          streamId: channel.id,
          name: channel.name,
          nameFold: channel.name.toLowerCase(),
          categoryId: Value(channel.categoryId),
          sortIndex: sortIndex,
          json: jsonEncode(encodeChannel(channel)),
        );
      case kCatalogKindVod:
        final vod = item as VodItem;
        return CatalogItemsCompanion.insert(
          sourceKey: sourceKey,
          kind: kind,
          streamId: vod.id,
          name: vod.name,
          nameFold: vod.name.toLowerCase(),
          categoryId: Value(vod.categoryId),
          categoryIdsJson: Value(
            vod.categoryIds.isEmpty ? null : jsonEncode(vod.categoryIds),
          ),
          rating: Value(vod.rating),
          sortIndex: sortIndex,
          json: jsonEncode(encodeVod(vod)),
        );
      case kCatalogKindSeries:
        final series = item as Series;
        return CatalogItemsCompanion.insert(
          sourceKey: sourceKey,
          kind: kind,
          streamId: series.id,
          name: series.name,
          nameFold: series.name.toLowerCase(),
          categoryId: Value(series.categoryId),
          categoryIdsJson: Value(
            series.categoryIds.isEmpty ? null : jsonEncode(series.categoryIds),
          ),
          rating: Value(series.rating),
          sortIndex: sortIndex,
          json: jsonEncode(encodeSeries(series)),
        );
      default:
        throw ArgumentError.value(kind, 'kind', 'unknown catalog kind');
    }
  }

  Object _decodeRow(String kind, String json) {
    final map = asMap(jsonDecode(json));
    return switch (kind) {
      kCatalogKindLive => decodeChannel(map),
      kCatalogKindVod => decodeVod(map),
      kCatalogKindSeries => decodeSeries(map),
      _ => throw ArgumentError.value(kind, 'kind', 'unknown catalog kind'),
    };
  }

  /// Every stored item of [kind], in provider order. Used while callers still
  /// expect the whole list; the windowed reads below replace it per surface.
  Future<List<T>> allItems<T>(String sourceKey, String kind) async {
    final rows =
        await (_db.select(_db.catalogItems)
              ..where(
                (t) => t.sourceKey.equals(sourceKey) & t.kind.equals(kind),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.sortIndex)]))
            .get();
    return rows
        .map((r) => _decodeRow(kind, r.json) as T)
        .toList(growable: false);
  }

  /// A windowed slice of [kind], provider order, optionally filtered to
  /// [categoryId] and/or a case-insensitive [search] substring of the name.
  Future<List<T>> pageItems<T>({
    required String sourceKey,
    required String kind,
    String? categoryId,
    String? search,
    required int offset,
    required int limit,
  }) async {
    final query = _db.select(_db.catalogItems)
      ..where((t) => _itemFilter(t, sourceKey, kind, categoryId, search))
      ..orderBy([(t) => OrderingTerm(expression: t.sortIndex)])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows
        .map((r) => _decodeRow(kind, r.json) as T)
        .toList(growable: false);
  }

  Future<int> countItems({
    required String sourceKey,
    required String kind,
    String? categoryId,
    String? search,
  }) async {
    final count = _db.catalogItems.streamId.count();
    final query = _db.selectOnly(_db.catalogItems)
      ..addColumns([count])
      ..where(
        _itemFilter(_db.catalogItems, sourceKey, kind, categoryId, search),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Expression<bool> _itemFilter(
    $CatalogItemsTable t,
    String sourceKey,
    String kind,
    String? categoryId,
    String? search,
  ) {
    var predicate = t.sourceKey.equals(sourceKey) & t.kind.equals(kind);
    if (categoryId != null) {
      predicate = predicate & _categoryPredicate(t, categoryId);
    }
    final trimmed = search?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      predicate = predicate & _likeContains(t.nameFold, trimmed);
    }
    return predicate;
  }

  /// Matches rows whose primary [CatalogItems.categoryId] is [categoryId] or
  /// whose multi-category JSON array contains it. The `"id"` form keeps the
  /// match token-exact inside the JSON string.
  Expression<bool> _categoryPredicate($CatalogItemsTable t, String categoryId) {
    final inList = _like(
      t.categoryIdsJson,
      '%"${_escapeLike(categoryId)}"%',
    );
    return t.categoryId.equals(categoryId) | inList;
  }

  Expression<bool> _likeContains(Expression<String> column, String raw) =>
      _like(column, '%${_escapeLike(raw)}%');

  /// `column LIKE pattern ESCAPE '\'`. The explicit escape char means a `%` /
  /// `_` the user typed into a search box (or a category id containing one) is
  /// matched literally instead of as a wildcard.
  Expression<bool> _like(Expression<String> column, String pattern) =>
      column.like(pattern, escapeChar: r'\');

  String _escapeLike(String raw) => raw
      .toLowerCase()
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  // -------------------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------------------

  Future<void> replaceCategories({
    required String sourceKey,
    required String kind,
    required List<Category> categories,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.catalogCategories)
            ..where((t) => t.sourceKey.equals(sourceKey) & t.kind.equals(kind)))
          .go();
      await _db.batch((batch) {
        for (var i = 0; i < categories.length; i++) {
          final category = categories[i];
          batch.insert(
            _db.catalogCategories,
            CatalogCategoriesCompanion.insert(
              sourceKey: sourceKey,
              kind: kind,
              categoryId: category.id,
              name: category.name,
              parentId: Value(category.parentId),
              sortIndex: i,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  Future<List<Category>> allCategories(String sourceKey, String kind) async {
    final rows =
        await (_db.select(_db.catalogCategories)
              ..where(
                (t) => t.sourceKey.equals(sourceKey) & t.kind.equals(kind),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.sortIndex)]))
            .get();
    return rows
        .map(
          (r) => decodeCategory(<String, Object?>{
            'category_id': r.categoryId,
            'category_name': r.name,
            'parent_id': r.parentId,
          }),
        )
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // EPG programmes
  // -------------------------------------------------------------------------

  Future<void> upsertProgrammes(List<EpgProgram> programmes) async {
    if (programmes.isEmpty) return;
    await _db.batch((batch) {
      for (final program in programmes) {
        batch.insert(
          _db.epgProgrammes,
          EpgProgrammesCompanion.insert(
            channelId: program.channelId,
            startMs: program.start.millisecondsSinceEpoch,
            endMs: program.end.millisecondsSinceEpoch,
            title: Value(program.title),
            subtitle: Value(program.subtitle),
            description: Value(program.description),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Replace the entire programme table with [programmes] (clear + insert),
  /// matching the "wipe and rewrite" semantics the persisted `epgGuide` blob
  /// had.
  Future<void> replaceProgrammes(List<EpgProgram> programmes) async {
    await _db.transaction(() async {
      await _db.delete(_db.epgProgrammes).go();
      await upsertProgrammes(programmes);
    });
  }

  Future<List<EpgProgram>> programmesEndingAfter(DateTime cutoff) async {
    final rows =
        await (_db.select(_db.epgProgrammes)
              ..where(
                (t) => t.endMs.isBiggerOrEqualValue(
                  cutoff.millisecondsSinceEpoch,
                ),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.startMs)]))
            .get();
    return rows.map(_programFromRow).toList(growable: false);
  }

  Future<void> pruneProgrammesEndingBefore(DateTime cutoff) async {
    await (_db.delete(_db.epgProgrammes)..where(
          (t) => t.endMs.isSmallerThanValue(
            cutoff.millisecondsSinceEpoch,
          ),
        ))
        .go();
  }

  EpgProgram _programFromRow(EpgProgrammeRow row) => EpgProgram(
    channelId: row.channelId,
    title: row.title,
    description: row.description,
    // EPG times are absolute schedule instants; the rest of the app treats
    // them as UTC (see domain_models `_asDateTimeOrNull`), so rebuild them
    // that way rather than in the host's local zone.
    start: DateTime.fromMillisecondsSinceEpoch(row.startMs, isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(row.endMs, isUtc: true),
    subtitle: row.subtitle,
  );

  // -------------------------------------------------------------------------
  // Key/value slots
  // -------------------------------------------------------------------------

  Future<String?> kvGet(String key) async {
    final row = await (_db.select(
      _db.kvCache,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> kvPut(String key, String value) async {
    await _db
        .into(_db.kvCache)
        .insertOnConflictUpdate(
          KvCacheCompanion.insert(
            key: key,
            value: value,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> kvDelete(String key) async {
    await (_db.delete(_db.kvCache)..where((t) => t.key.equals(key))).go();
  }

  // -------------------------------------------------------------------------
  // Maintenance
  // -------------------------------------------------------------------------

  Future<bool> isEmpty() async {
    final any = await (_db.select(
      _db.catalogItems,
    )..limit(1)).getSingleOrNull();
    return any == null;
  }

  Future<void> clearAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.catalogItems).go();
      await _db.delete(_db.catalogCategories).go();
      await _db.delete(_db.epgProgrammes).go();
      await _db.delete(_db.kvCache).go();
    });
  }

  /// Full dump of every table, for the rollback `CacheService` performs when a
  /// source switch fails partway.
  Future<CatalogSnapshot> snapshot() async => CatalogSnapshot(
    items: await _db.select(_db.catalogItems).get(),
    categories: await _db.select(_db.catalogCategories).get(),
    programmes: await _db.select(_db.epgProgrammes).get(),
    kv: await _db.select(_db.kvCache).get(),
  );

  /// Replace every table's contents with [snapshot] in one transaction.
  Future<void> restore(CatalogSnapshot snapshot) async {
    await _db.transaction(() async {
      await _db.delete(_db.catalogItems).go();
      await _db.delete(_db.catalogCategories).go();
      await _db.delete(_db.epgProgrammes).go();
      await _db.delete(_db.kvCache).go();
      await _db.batch((batch) {
        batch
          ..insertAll(_db.catalogItems, snapshot.items)
          ..insertAll(_db.catalogCategories, snapshot.categories)
          ..insertAll(_db.epgProgrammes, snapshot.programmes)
          ..insertAll(_db.kvCache, snapshot.kv);
      });
    });
  }
}

/// Opaque full-database snapshot passed between [CatalogRepository.snapshot]
/// and [CatalogRepository.restore].
class CatalogSnapshot {
  const CatalogSnapshot({
    required this.items,
    required this.categories,
    required this.programmes,
    required this.kv,
  });

  final List<CatalogItemRow> items;
  final List<CatalogCategoryRow> categories;
  final List<EpgProgrammeRow> programmes;
  final List<KvCacheRow> kv;
}
