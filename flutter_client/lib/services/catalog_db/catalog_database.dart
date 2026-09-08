import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

part 'catalog_database.g.dart';

/// One row per catalog stream (live channel, VOD item, or series), keyed by
/// `(sourceKey, kind, streamId)`. The full domain payload is kept as [json];
/// the promoted columns exist only so the app can page, sort, filter, and
/// search in SQLite instead of materializing the whole catalog in Dart.
@DataClassName('CatalogItemRow')
class CatalogItems extends Table {
  /// Which configured source this row belongs to (Xtream server + account,
  /// hashed). Lets a future multi-source setup share one database.
  TextColumn get sourceKey => text()();

  /// `live` | `vod` | `series`.
  TextColumn get kind => text()();

  /// Provider stream/series id.
  IntColumn get streamId => integer()();

  TextColumn get name => text()();

  /// Case-folded, accent-stripped [name] for `LIKE` search and ordering.
  TextColumn get nameFold => text()();

  /// Primary category id (provider order). Null for uncategorized rows.
  TextColumn get categoryId => text().nullable()();

  /// JSON array of every category id this row belongs to, when the provider
  /// reports more than one. Null when there is only [categoryId].
  TextColumn get categoryIdsJson => text().nullable()();

  RealColumn get rating => real().nullable()();

  /// Position in the provider's original ordering, so the default sort is
  /// stable without a name comparison.
  IntColumn get sortIndex => integer()();

  /// The full serialized domain object (`Channel` / `VodItem` / `Series`),
  /// same shape `CacheService` used to persist.
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {sourceKey, kind, streamId};
}

@DataClassName('CatalogCategoryRow')
class CatalogCategories extends Table {
  TextColumn get sourceKey => text()();
  TextColumn get kind => text()();
  TextColumn get categoryId => text()();
  TextColumn get name => text()();

  /// Parent category id as the provider reports it: `0` means "no parent"
  /// (mirrors `Category.parentId`).
  IntColumn get parentId => integer().withDefault(const Constant(0))();
  IntColumn get sortIndex => integer()();

  @override
  Set<Column> get primaryKey => {sourceKey, kind, categoryId};
}

/// EPG programmes, keyed by `(channelId, startMs)`. Replaces the capped
/// `epgGuide` JSON blob `CacheService` persisted.
@DataClassName('EpgProgrammeRow')
class EpgProgrammes extends Table {
  TextColumn get channelId => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get subtitle => text().nullable()();
  TextColumn get description => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {channelId, startMs};
}

/// Small key/value slots that used to live as individual `CacheService` keys
/// (`sourceType`, `viewers`, ...). [updatedAtMs] backs `getIfFresh`.
@DataClassName('KvCacheRow')
class KvCache extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [CatalogItems, CatalogCategories, EpgProgrammes, KvCache],
)
class CatalogDatabase extends _$CatalogDatabase {
  CatalogDatabase(super.e);

  /// In-memory database for tests.
  CatalogDatabase.memory() : super(NativeDatabase.memory());

  /// Opens (creating if needed) `m3u_tv_catalog.db` inside [directory], which
  /// callers resolve the same way `_createAppStateStores` resolves the JSON
  /// stores (Caches on tvOS, Documents on mobile, app-support on desktop).
  factory CatalogDatabase.open(Directory directory) {
    final file = File(p.join(directory.path, _databaseFile));
    return CatalogDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (db) {
          db
            ..execute('PRAGMA journal_mode=WAL')
            ..execute('PRAGMA synchronous=NORMAL');
        },
      ),
    );
  }

  static const _databaseFile = 'm3u_tv_catalog.db';

  @override
  int get schemaVersion => 1;
}
