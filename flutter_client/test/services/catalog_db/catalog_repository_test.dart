import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';

VodItem _vod(
  int id,
  String name, {
  String? category,
  double? rating,
  String? year,
}) => VodItem(
  id: id,
  name: name,
  streamUrl: 'http://host/movie/$id.mp4',
  containerExtension: 'mp4',
  categoryId: category,
  rating: rating,
  year: year,
);

Channel _channel(int id, String name, {String? category}) => Channel(
  id: id,
  name: name,
  streamUrl: 'http://host/live/$id.m3u8',
  categoryId: category,
);

void main() {
  late CatalogDatabase db;
  late CatalogRepository repo;

  setUp(() {
    db = CatalogDatabase.memory();
    repo = CatalogRepository(db);
  });

  tearDown(() => db.close());

  test(
    'replaceItems + allItems round-trips through the codec, in order',
    () async {
      await repo.replaceItems(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        items: [_vod(10, 'Zeta'), _vod(20, 'Alpha', rating: 7.5)],
      );

      final items = await repo.allItems<VodItem>('s1', kCatalogKindVod);
      expect(items.map((v) => v.name), [
        'Zeta',
        'Alpha',
      ]); // provider order kept
      expect(items[1].rating, 7.5);
      expect(items[0].streamUrl, 'http://host/movie/10.mp4');
    },
  );

  test(
    'allItems decodes large catalogs off the main isolate, in order',
    () async {
      // Above the inline threshold, so the rows decode on a spawned isolate and
      // the models come back across it.
      await repo.replaceItems(
        sourceKey: 's1',
        kind: kCatalogKindLive,
        items: [for (var i = 1; i <= 1200; i++) _channel(i, 'Channel $i')],
      );

      final items = await repo.allItems<Channel>('s1', kCatalogKindLive);
      expect(items, hasLength(1200));
      expect(items.first.name, 'Channel 1');
      expect(items.last.streamUrl, 'http://host/live/1200.m3u8');
    },
  );

  test(
    'replaceItems keeps every element when stream ids are missing or duplicated',
    () async {
      await repo.replaceItems(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        items: [
          _vod(0, 'No id A'),
          _vod(0, 'No id B'),
          _vod(50, 'Real'),
          _vod(50, 'Dup of real'),
        ],
      );

      final items = await repo.allItems<VodItem>('s1', kCatalogKindVod);
      expect(items.map((v) => v.name), [
        'No id A',
        'No id B',
        'Real',
        'Dup of real',
      ]);
      expect(await repo.countItems(sourceKey: 's1', kind: kCatalogKindVod), 4);
    },
  );

  test('replaceItems fully swaps the previous catalog for that kind', () async {
    await repo.replaceItems(
      sourceKey: 's1',
      kind: kCatalogKindVod,
      items: [_vod(1, 'Old A'), _vod(2, 'Old B')],
    );
    await repo.replaceItems(
      sourceKey: 's1',
      kind: kCatalogKindVod,
      items: [_vod(3, 'New')],
    );

    final items = await repo.allItems<VodItem>('s1', kCatalogKindVod);
    expect(items.map((v) => v.id), [3]);
  });

  test('a different kind and sourceKey are untouched by a replace', () async {
    await repo.replaceItems(
      sourceKey: 's1',
      kind: kCatalogKindLive,
      items: [_channel(1, 'Chan')],
    );
    await repo.replaceItems(
      sourceKey: 's2',
      kind: kCatalogKindVod,
      items: [_vod(1, 'Movie')],
    );

    await repo.replaceItems(
      sourceKey: 's1',
      kind: kCatalogKindVod,
      items: [_vod(9, 'Other')],
    );

    expect((await repo.allItems<Channel>('s1', kCatalogKindLive)).length, 1);
    expect((await repo.allItems<VodItem>('s2', kCatalogKindVod)).length, 1);
  });

  test(
    'pageItems windows the result and countItems reports the total',
    () async {
      await repo.replaceItems(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        items: List.generate(50, (i) => _vod(i, 'Movie $i')),
      );

      final page = await repo.pageItems<VodItem>(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        offset: 20,
        limit: 10,
      );
      expect(page.map((v) => v.id), List.generate(10, (i) => 20 + i));
      expect(
        await repo.countItems(sourceKey: 's1', kind: kCatalogKindVod),
        50,
      );
    },
  );

  test(
    'pageItems filters by primary category and by multi-category json',
    () async {
      await repo.replaceItems(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        items: [
          _vod(1, 'In A', category: 'a'),
          _vod(2, 'In B', category: 'b'),
          const VodItem(
            id: 3,
            name: 'In A and C',
            streamUrl: 'http://host/movie/3.mp4',
            containerExtension: 'mp4',
            categoryId: 'c',
            categoryIds: ['c', 'a'],
          ),
        ],
      );

      final inA = await repo.pageItems<VodItem>(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        categoryId: 'a',
        offset: 0,
        limit: 50,
      );
      expect(inA.map((v) => v.id).toSet(), {1, 3});
      expect(
        await repo.countItems(
          sourceKey: 's1',
          kind: kCatalogKindVod,
          categoryId: 'a',
        ),
        2,
      );
    },
  );

  test(
    'search matches case-insensitively and escapes LIKE metacharacters',
    () async {
      await repo.replaceItems(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        items: [
          _vod(1, 'The Matrix'),
          _vod(2, 'matrix reloaded'),
          _vod(3, '50% Off'),
        ],
      );

      final matrix = await repo.pageItems<VodItem>(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        search: 'MATRIX',
        offset: 0,
        limit: 50,
      );
      expect(matrix.map((v) => v.id).toSet(), {1, 2});

      final percent = await repo.pageItems<VodItem>(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        search: '50%',
        offset: 0,
        limit: 50,
      );
      expect(percent.map((v) => v.id), [3]);
    },
  );

  group('CatalogSort', () {
    setUp(() async {
      await repo.replaceItems(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        items: [
          _vod(1, 'AAAA Highest', rating: 9, year: '2020'),
          _vod(2, 'BBBB Mid', rating: 7, year: '1999'),
          _vod(3, 'CCCC Unrated'),
          _vod(4, 'DDDD Third', rating: 8, year: '2010'),
        ],
      );
    });

    Future<List<String>> namesFor(CatalogSort sort) async {
      final rows = await repo.pageItems<VodItem>(
        sourceKey: 's1',
        kind: kCatalogKindVod,
        sort: sort,
        offset: 0,
        limit: 50,
      );
      return rows.map((v) => v.name).toList();
    }

    test('providerOrder matches insertion order (the default)', () async {
      expect(await namesFor(CatalogSort.providerOrder), [
        'AAAA Highest',
        'BBBB Mid',
        'CCCC Unrated',
        'DDDD Third',
      ]);
    });

    test('ratingDesc sinks unrated rows to the bottom', () async {
      expect(await namesFor(CatalogSort.ratingDesc), [
        'AAAA Highest',
        'DDDD Third',
        'BBBB Mid',
        'CCCC Unrated',
      ]);
    });

    test(
      'yearDesc (newest first) sinks unknown-year rows to the bottom',
      () async {
        expect(await namesFor(CatalogSort.yearDesc), [
          'AAAA Highest', // 2020
          'DDDD Third', // 2010
          'BBBB Mid', // 1999
          'CCCC Unrated', // no year
        ]);
      },
    );

    test(
      'yearAsc (oldest first) also sinks unknown-year rows to the bottom',
      () async {
        expect(await namesFor(CatalogSort.yearAsc), [
          'BBBB Mid', // 1999
          'DDDD Third', // 2010
          'AAAA Highest', // 2020
          'CCCC Unrated', // no year - last, not first
        ]);
      },
    );

    test(
      'favoritesFirst floats favorites above the rest, each group in sort order',
      () async {
        final rows = await repo.pageItems<VodItem>(
          sourceKey: 's1',
          kind: kCatalogKindVod,
          sort: CatalogSort.ratingDesc,
          favoritesFirst: {2, 3, 99},
          offset: 0,
          limit: 50,
        );
        expect(rows.map((v) => v.name), [
          'BBBB Mid', // favorite, rated
          'CCCC Unrated', // favorite, unrated
          'AAAA Highest',
          'DDDD Third',
        ]);
      },
    );

    test('favoritesFirst pages consistently across offsets', () async {
      Future<List<String>> page(int offset) async {
        final rows = await repo.pageItems<VodItem>(
          sourceKey: 's1',
          kind: kCatalogKindVod,
          favoritesFirst: {4},
          offset: offset,
          limit: 2,
        );
        return rows.map((v) => v.name).toList();
      }

      expect(await page(0), ['DDDD Third', 'AAAA Highest']);
      expect(await page(2), ['BBBB Mid', 'CCCC Unrated']);
    });
  });

  test('categories round-trip in provider order', () async {
    await repo.replaceCategories(
      sourceKey: 's1',
      kind: kCatalogKindVod,
      categories: const [
        Category(id: '2', name: 'Action'),
        Category(id: '1', name: 'Kids', parentId: 9),
      ],
    );

    final categories = await repo.allCategories('s1', kCatalogKindVod);
    expect(categories.map((c) => c.name), ['Action', 'Kids']);
    expect(categories[1].parentId, 9);
  });

  test(
    'EPG upsert replaces same-key rows and prune drops ended programmes',
    () async {
      final base = DateTime(2026, 1, 1, 12);
      await repo.upsertProgrammes([
        EpgProgram(
          channelId: 'c1',
          title: 'Old title',
          description: '',
          start: base,
          end: base.add(const Duration(hours: 1)),
        ),
        EpgProgram(
          channelId: 'c1',
          title: 'Later',
          description: '',
          start: base.add(const Duration(hours: 2)),
          end: base.add(const Duration(hours: 3)),
        ),
      ]);
      // Same (channelId, start) -> upsert overwrites the title.
      await repo.upsertProgrammes([
        EpgProgram(
          channelId: 'c1',
          title: 'New title',
          description: 'd',
          start: base,
          end: base.add(const Duration(hours: 1)),
        ),
      ]);

      var all = await repo.programmesEndingAfter(DateTime(2000));
      expect(all.length, 2);
      expect(all.first.title, 'New title');

      await repo.pruneProgrammesEndingBefore(
        base.add(const Duration(minutes: 90)),
      );
      all = await repo.programmesEndingAfter(DateTime(2000));
      expect(all.map((p) => p.title), ['Later']);
    },
  );

  test('kv slots round-trip and delete', () async {
    await repo.kvPut('sourceType', 'xtream');
    expect(await repo.kvGet('sourceType'), 'xtream');
    await repo.kvPut('sourceType', 'xtream-2');
    expect(await repo.kvGet('sourceType'), 'xtream-2');
    await repo.kvDelete('sourceType');
    expect(await repo.kvGet('sourceType'), isNull);
  });

  test(
    'kvUpdatedAt returns the recorded write time, null when absent',
    () async {
      expect(await repo.kvUpdatedAt('__ts_liveStreams'), isNull);
      await repo.kvPut('__ts_liveStreams', '', updatedAtMs: 1234);
      expect(await repo.kvUpdatedAt('__ts_liveStreams'), 1234);
      await repo.kvDelete('__ts_liveStreams');
      expect(await repo.kvUpdatedAt('__ts_liveStreams'), isNull);
    },
  );

  group('activeItemById / activeItemsByIds', () {
    setUp(() async {
      await repo.replaceItems(
        sourceKey: CatalogRepository.activeSource,
        kind: kCatalogKindVod,
        items: [
          _vod(1, 'One'),
          _vod(2, 'Two'),
          _vod(3, 'Three'),
        ],
      );
    });

    test('activeItemById resolves a row by id', () async {
      final item = await repo.activeItemById<VodItem>(
        kind: kCatalogKindVod,
        id: 2,
      );
      expect(item?.name, 'Two');
    });

    test('activeItemById returns null for an unknown id', () async {
      final item = await repo.activeItemById<VodItem>(
        kind: kCatalogKindVod,
        id: 999,
      );
      expect(item, isNull);
    });

    test('activeItemsByIds resolves only the requested ids', () async {
      final items = await repo.activeItemsByIds<VodItem>(
        kind: kCatalogKindVod,
        ids: {1, 3, 999},
      );
      expect(items.map((v) => v.name).toSet(), {'One', 'Three'});
    });

    test('activeItemsByIds returns empty for an empty id set', () async {
      final items = await repo.activeItemsByIds<VodItem>(
        kind: kCatalogKindVod,
        ids: {},
      );
      expect(items, isEmpty);
    });
  });

  test('activeCategoryCounts matches per-category countActiveItems', () async {
    await repo.replaceItems(
      sourceKey: CatalogRepository.activeSource,
      kind: kCatalogKindVod,
      items: [
        _vod(1, 'A', category: '10'),
        _vod(2, 'B', category: '10'),
        _vod(3, 'C', category: '20'),
      ],
    );

    final counts = await repo.activeCategoryCounts(
      kind: kCatalogKindVod,
      categoryIds: ['10', '20', '30'],
    );
    expect(counts, {'10': 2, '20': 1, '30': 0});
  });
}
