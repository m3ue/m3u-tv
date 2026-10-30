import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_store.dart';
import 'package:m3u_tv/services/json_isolate.dart';

/// Which promoted column (if any) a windowed page/count query orders by,
/// beyond the provider's own [CatalogItems.sortIndex]. A dedicated enum
/// rather than a `sortByXDesc` bool per dimension, so a new sort dimension
/// is one more case here instead of one more parameter on
/// `CatalogRepository.pageItems`.
enum CatalogSort {
  /// [CatalogItems.sortIndex] - the provider's own order.
  providerOrder,
  ratingDesc,
  yearDesc,
  yearAsc,

  /// [CatalogItems.recency], newest first.
  recentDesc,
}

/// Domain-facing wrapper over [CatalogDatabase]. Encodes/decodes rows through
/// `catalog_codec`, keeps the promoted columns in sync, and exposes both the
/// full-list reads the app still relies on and the windowed page/count reads
/// the grids will move to.
class CatalogRepository implements EpgProgrammeStore {
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
    CatalogSort sort = CatalogSort.providerOrder,
    Set<int> favoritesFirst = const {},
    required int offset,
    required int limit,
  }) => pageItems<T>(
    sourceKey: activeSource,
    kind: kind,
    categoryId: categoryId,
    search: search,
    sort: sort,
    favoritesFirst: favoritesFirst,
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

  /// A single active-source row by id, or null if it isn't in the current
  /// catalog. For resolving a bare id (a deep link, a push notification, a
  /// related-item tap) to the full domain object without holding the whole
  /// catalog in memory to `firstWhere` against.
  Future<T?> activeItemById<T>({required String kind, required int id}) async {
    final row =
        await (_db.select(_db.catalogItems)..where(
              (t) =>
                  t.sourceKey.equals(activeSource) &
                  t.kind.equals(kind) &
                  t.streamId.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _decodeRow(kind, row.json) as T;
  }

  /// Active-source rows matching any id in [ids], in no particular order. For
  /// resolving a bounded set of ids (favorites, Continue Watching entries) -
  /// callers needing catalog order should re-sort by the input list.
  Future<List<T>> activeItemsByIds<T>({
    required String kind,
    required Set<int> ids,
  }) async {
    if (ids.isEmpty) return const [];
    final rows =
        await (_db.select(_db.catalogItems)..where(
              (t) =>
                  t.sourceKey.equals(activeSource) &
                  t.kind.equals(kind) &
                  t.streamId.isIn(ids),
            ))
            .get();
    return rows
        .map((r) => _decodeRow(kind, r.json) as T)
        .toList(
          growable: false,
        );
  }

  /// Per-category membership counts among the active-source rows of [kind],
  /// matching [_categoryPredicate]'s primary-or-overlap semantics (so a
  /// dynamic multi-category item counts toward every category it belongs to).
  /// One query per category id - cheap for the tens of categories a real
  /// catalog has, unlike scanning every row in Dart.
  Future<Map<String, int>> activeCategoryCounts({
    required String kind,
    required List<String> categoryIds,
  }) async {
    final counts = await Future.wait(
      categoryIds.map(
        (id) => countActiveItems(kind: kind, categoryId: id),
      ),
    );
    return {
      for (var i = 0; i < categoryIds.length; i++) categoryIds[i]: counts[i],
    };
  }

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
  }) {
    // Every row is a jsonEncode plus a companion; for a large library that
    // per-row work (not the SQL, which drift already runs off-thread) blocked
    // the UI isolate for the length of a catalog refresh.
    if (!_offloadWrites || items.length < _offloadThresholdRows) {
      return _replaceItemsOn(_db, sourceKey, kind, items);
    }
    return _db.computeWithDatabase(
      connect: CatalogDatabase.new,
      computation: (db) => _replaceItemsOn(db, sourceKey, kind, items),
    );
  }

  /// No isolates (and so no `computeWithDatabase`) on the web.
  static const bool _offloadWrites = !kIsWeb;

  static Future<void> _replaceItemsOn(
    CatalogDatabase db,
    String sourceKey,
    String kind,
    List<Object> items,
  ) async {
    await db.transaction(() async {
      await (db.delete(db.catalogItems)
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
      await db.batch((batch) {
        for (var i = 0; i < items.length; i++) {
          var row = _rowFor(sourceKey, kind, items[i], i);
          if (row.streamId.value <= 0 || !usedIds.add(row.streamId.value)) {
            final surrogate = -(i + 1);
            usedIds.add(surrogate);
            row = row.copyWith(streamId: Value(surrogate));
          }
          batch.insert(db.catalogItems, row, mode: InsertMode.insertOrReplace);
        }
      });
    });
  }

  static CatalogItemsCompanion _rowFor(
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
          year: Value(_parseYear(vod.year)),
          recency: Value(vod.addedAt),
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
          year: Value(_parseYear(series.year)),
          recency: Value(series.lastModifiedAt),
          sortIndex: sortIndex,
          json: jsonEncode(encodeSeries(series)),
        );
      default:
        throw ArgumentError.value(kind, 'kind', 'unknown catalog kind');
    }
  }

  /// Parses a domain object's four-digit `year` string into the promoted
  /// column's int, or null for anything absent/malformed.
  static int? _parseYear(String? year) =>
      year == null ? null : int.tryParse(year);

  static Object _decodeRow(String kind, String json) {
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
    final decoded = await _decodeRowsOffMainIsolate(kind, [
      for (final row in rows) row.json,
    ]);
    return List<T>.from(decoded, growable: false);
  }

  /// Below this many rows the decode is quicker than spawning an isolate.
  static const int _offloadThresholdRows = 500;

  /// Decodes whole-catalog reads (tens of thousands of rows, one jsonDecode
  /// each) on a short-lived isolate: inline, it blocked the UI thread for
  /// seconds during boot's cache hydration, stalling every frame of the
  /// launch splash. Static so the closure can't capture the repository, and
  /// Isolate.run hands the result back without copying it.
  static Future<List<Object>> _decodeRowsOffMainIsolate(
    String kind,
    List<String> jsons,
  ) {
    List<Object> decodeAll() => [
      for (final json in jsons) _decodeRow(kind, json),
    ];
    if (jsons.length < _offloadThresholdRows) return Future.value(decodeAll());
    return runOffMainIsolate(decodeAll);
  }

  /// A windowed slice of [kind], provider order, optionally filtered to
  /// [categoryId] and/or a case-insensitive [search] substring of the name,
  /// ordered per [sort] (see [_orderingFor]). Rows whose id is in
  /// [favoritesFirst] are ordered ahead of the rest, each group still in
  /// [sort] order.
  Future<List<T>> pageItems<T>({
    required String sourceKey,
    required String kind,
    String? categoryId,
    String? search,
    CatalogSort sort = CatalogSort.providerOrder,
    Set<int> favoritesFirst = const {},
    required int offset,
    required int limit,
  }) async {
    final query = _db.select(_db.catalogItems)
      ..where((t) => _itemFilter(t, sourceKey, kind, categoryId, search))
      ..orderBy([
        if (favoritesFirst.isNotEmpty)
          (t) => OrderingTerm(
            expression: t.streamId.isIn(favoritesFirst),
            mode: OrderingMode.desc,
          ),
        ..._orderingFor(sort),
      ])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows
        .map((r) => _decodeRow(kind, r.json) as T)
        .toList(growable: false);
  }

  /// Ordering terms for [sort], always ending in [CatalogItems.sortIndex] as
  /// a stable tiebreaker. `ratingDesc`/`yearDesc`/`recentDesc` rely on SQLite's default
  /// NULL-sorts-smaller-than-anything behavior to sink unrated/unknown-year
  /// rows to the bottom for free; `yearAsc` orders oldest-first but still
  /// wants unknown years last rather than first, so it asks for that
  /// explicitly via `nulls: NullsOrder.last`.
  List<OrderingTerm Function($CatalogItemsTable)> _orderingFor(
    CatalogSort sort,
  ) {
    OrderingTerm tiebreaker($CatalogItemsTable t) =>
        OrderingTerm(expression: t.sortIndex);
    return switch (sort) {
      CatalogSort.providerOrder => [tiebreaker],
      CatalogSort.ratingDesc => [
        (t) => OrderingTerm(expression: t.rating, mode: OrderingMode.desc),
        tiebreaker,
      ],
      CatalogSort.yearDesc => [
        (t) => OrderingTerm(expression: t.year, mode: OrderingMode.desc),
        tiebreaker,
      ],
      CatalogSort.yearAsc => [
        (t) => OrderingTerm(
          expression: t.year,
          nulls: NullsOrder.last,
        ),
        tiebreaker,
      ],
      CatalogSort.recentDesc => [
        (t) => OrderingTerm(expression: t.recency, mode: OrderingMode.desc),
        tiebreaker,
      ],
    };
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

  Future<void> upsertProgrammes(List<EpgProgram> programmes) {
    if (programmes.isEmpty) return Future.value();
    if (!_offloadWrites || programmes.length < _offloadThresholdRows) {
      return _upsertProgrammesOn(_db, programmes);
    }
    return _db.computeWithDatabase(
      connect: CatalogDatabase.new,
      computation: (db) => _upsertProgrammesOn(db, programmes),
    );
  }

  /// Replace the entire programme table with [programmes] (clear + insert),
  /// matching the "wipe and rewrite" semantics the persisted `epgGuide` blob
  /// had.
  Future<void> replaceProgrammes(List<EpgProgram> programmes) {
    if (!_offloadWrites || programmes.length < _offloadThresholdRows) {
      return _replaceProgrammesOn(_db, programmes);
    }
    return _db.computeWithDatabase(
      connect: CatalogDatabase.new,
      computation: (db) => _replaceProgrammesOn(db, programmes),
    );
  }

  /// Replaces the stored programmes of just the channels in [byChannel]
  /// (deleting a channel's rows even when its new list is empty), then drops
  /// every programme that ended before [pruneBefore]. Mirrors how the
  /// in-memory guide replaces a fetched channel's schedule, so a rescheduled
  /// slot doesn't linger beside its replacement, without rewriting channels
  /// that didn't change.
  Future<void> replaceChannelProgrammes(
    Map<String, List<EpgProgram>> byChannel, {
    DateTime? pruneBefore,
  }) {
    final rows = byChannel.values.fold<int>(0, (n, list) => n + list.length);
    if (!_offloadWrites || rows < _offloadThresholdRows) {
      return _replaceChannelProgrammesOn(_db, byChannel, pruneBefore);
    }
    return _db.computeWithDatabase(
      connect: CatalogDatabase.new,
      computation: (db) =>
          _replaceChannelProgrammesOn(db, byChannel, pruneBefore),
    );
  }

  static Future<void> _replaceChannelProgrammesOn(
    CatalogDatabase db,
    Map<String, List<EpgProgram>> byChannel,
    DateTime? pruneBefore,
  ) => db.transaction(() async {
    if (byChannel.isNotEmpty) {
      await (db.delete(
        db.epgProgrammes,
      )..where((t) => t.channelId.isIn(byChannel.keys))).go();
      await _upsertProgrammesOn(db, [
        for (final programmes in byChannel.values) ...programmes,
      ]);
    }
    if (pruneBefore != null) {
      await (db.delete(db.epgProgrammes)..where(
            (t) => t.endMs.isSmallerThanValue(
              pruneBefore.millisecondsSinceEpoch,
            ),
          ))
          .go();
    }
  });

  static Future<void> _replaceProgrammesOn(
    CatalogDatabase db,
    List<EpgProgram> programmes,
  ) => db.transaction(() async {
    await db.delete(db.epgProgrammes).go();
    await _upsertProgrammesOn(db, programmes);
  });

  static Future<void> _upsertProgrammesOn(
    CatalogDatabase db,
    List<EpgProgram> programmes,
  ) async {
    if (programmes.isEmpty) return;
    await db.batch((batch) {
      for (final program in programmes) {
        batch.insert(
          db.epgProgrammes,
          EpgProgrammesCompanion.insert(
            channelId: program.channelId,
            startMs: program.start.millisecondsSinceEpoch,
            endMs: program.end.millisecondsSinceEpoch,
            title: Value(program.title),
            subtitle: Value(program.subtitle),
            description: Value(program.description),
            iconUrl: Value(program.iconUrl),
            posterUrl: Value(program.posterUrl),
            backdropUrl: Value(program.backdropUrl),
            category: Value(program.category),
            rating: Value(program.rating),
            season: Value(program.season),
            episode: Value(program.episode),
            year: Value(program.year),
            isNew: Value(program.isNew),
            isPremiere: Value(program.isPremiere),
            isRepeat: Value(program.isRepeat),
            isPlaceholder: Value(program.isPlaceholder),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Every programme ending at or after [cutoff], start-ordered. A full-guide
  /// read (boot hydration) can be 100k+ rows, so above the offload threshold
  /// both the query and the row mapping run on a background isolate.
  Future<List<EpgProgram>> programmesEndingAfter(DateTime cutoff) async {
    if (_offloadWrites &&
        await _countProgrammesEndingAfter(cutoff) >= _offloadThresholdRows) {
      // The computation must capture only sendable values (not `this` or a
      // drift expression), so it is built apart from the count query.
      return _db.computeWithDatabase(
        connect: CatalogDatabase.new,
        computation: (db) => _programmesEndingAfterOn(db, cutoff),
      );
    }
    return _programmesEndingAfterOn(_db, cutoff);
  }

  Future<int> _countProgrammesEndingAfter(DateTime cutoff) {
    final count = _db.epgProgrammes.channelId.count();
    return (_db.selectOnly(_db.epgProgrammes)
          ..addColumns([count])
          ..where(
            _db.epgProgrammes.endMs.isBiggerOrEqualValue(
              cutoff.millisecondsSinceEpoch,
            ),
          ))
        .map((row) => row.read(count) ?? 0)
        .getSingle();
  }

  static Future<List<EpgProgram>> _programmesEndingAfterOn(
    CatalogDatabase db,
    DateTime cutoff,
  ) async {
    final rows =
        await (db.select(db.epgProgrammes)
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

  @override
  Future<void> applyEpgOps(List<EpgStoreOp> ops) {
    if (ops.isEmpty) return Future.value();
    var rows = 0;
    for (final op in ops) {
      rows += switch (op) {
        EpgReplaceChannels(:final byChannel) ||
        EpgMergeIntoChannels(:final byChannel) => byChannel.values.fold(
          0,
          (n, list) => n + list.length,
        ),
        EpgPruneBefore() => 0,
      };
    }
    if (!_offloadWrites || rows < _offloadThresholdRows) {
      return _applyEpgOpsOn(_db, ops);
    }
    return _db.computeWithDatabase(
      connect: CatalogDatabase.new,
      computation: (db) => _applyEpgOpsOn(db, ops),
    );
  }

  static Future<void> _applyEpgOpsOn(
    CatalogDatabase db,
    List<EpgStoreOp> ops,
  ) => db.transaction(() async {
    for (final op in ops) {
      switch (op) {
        case EpgReplaceChannels(:final byChannel):
          if (byChannel.isEmpty) continue;
          await (db.delete(
            db.epgProgrammes,
          )..where((t) => t.channelId.isIn(byChannel.keys))).go();
          await _upsertProgrammesOn(db, [
            for (final programmes in byChannel.values) ...programmes,
          ]);
        case EpgMergeIntoChannels(:final byChannel):
          for (final MapEntry(key: channelId, value: programmes)
              in byChannel.entries) {
            final sorted = [...programmes]
              ..sort((a, b) => a.start.compareTo(b.start));
            for (final (start, end) in epgDisjointSpans(sorted)) {
              await (db.delete(db.epgProgrammes)..where(
                    (t) =>
                        t.channelId.equals(channelId) &
                        t.startMs.isSmallerThanValue(
                          end.millisecondsSinceEpoch,
                        ) &
                        t.endMs.isBiggerThanValue(start.millisecondsSinceEpoch),
                  ))
                  .go();
            }
            await _upsertProgrammesOn(db, programmes);
          }
        case EpgPruneBefore(:final cutoff):
          await (db.delete(db.epgProgrammes)..where(
                (t) =>
                    t.endMs.isSmallerThanValue(cutoff.millisecondsSinceEpoch),
              ))
              .go();
      }
    }
  });

  @override
  Future<Map<String, List<EpgProgram>>> programmesForChannels(
    Set<String> channelIds,
  ) async {
    if (channelIds.isEmpty) return const {};
    final rows =
        await (_db.select(_db.epgProgrammes)
              ..where((t) => t.channelId.isIn(channelIds))
              ..orderBy([(t) => OrderingTerm(expression: t.startMs)]))
            .get();
    return _groupByChannel(rows);
  }

  @override
  Future<Map<String, List<EpgProgram>>> programmesBetween(
    DateTime endAfter,
    DateTime startBefore, {
    Set<String>? channelIds,
  }) async {
    if (channelIds != null && channelIds.isEmpty) return const {};
    final rows =
        await (_db.select(_db.epgProgrammes)
              ..where((t) {
                final window =
                    t.endMs.isBiggerThanValue(endAfter.millisecondsSinceEpoch) &
                    t.startMs.isSmallerThanValue(
                      startBefore.millisecondsSinceEpoch,
                    );
                return channelIds == null
                    ? window
                    : window & t.channelId.isIn(channelIds);
              })
              ..orderBy([(t) => OrderingTerm(expression: t.startMs)]))
            .get();
    return _groupByChannel(rows);
  }

  static Map<String, List<EpgProgram>> _groupByChannel(
    List<EpgProgrammeRow> rows,
  ) {
    final byChannel = <String, List<EpgProgram>>{};
    for (final row in rows) {
      byChannel.putIfAbsent(row.channelId, () => []).add(_programFromRow(row));
    }
    return byChannel;
  }

  static EpgProgram _programFromRow(EpgProgrammeRow row) => EpgProgram(
    channelId: row.channelId,
    title: row.title,
    description: row.description,
    // EPG times are absolute schedule instants; the rest of the app treats
    // them as UTC (see domain_models `_asDateTimeOrNull`), so rebuild them
    // that way rather than in the host's local zone.
    start: DateTime.fromMillisecondsSinceEpoch(row.startMs, isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(row.endMs, isUtc: true),
    subtitle: row.subtitle,
    iconUrl: row.iconUrl,
    posterUrl: row.posterUrl,
    backdropUrl: row.backdropUrl,
    category: row.category,
    rating: row.rating,
    season: row.season,
    episode: row.episode,
    year: row.year,
    isNew: row.isNew,
    isPremiere: row.isPremiere,
    isRepeat: row.isRepeat,
    isPlaceholder: row.isPlaceholder,
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

  /// The `updatedAtMs` recorded for [key]'s slot, or null when it has never
  /// been written. `CacheService` reads this back as the write time for the
  /// SQLite-backed catalog keys' staleness check.
  Future<int?> kvUpdatedAt(String key) async {
    final row = await (_db.select(
      _db.kvCache,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.updatedAtMs;
  }

  Future<void> kvPut(String key, String value, {int? updatedAtMs}) async {
    await _db
        .into(_db.kvCache)
        .insertOnConflictUpdate(
          KvCacheCompanion.insert(
            key: key,
            value: value,
            updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
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
