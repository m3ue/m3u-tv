import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_import.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

VodItem _vod(int id, String name, {String? category, double? rating}) =>
    VodItem(
      id: id,
      name: name,
      streamUrl: 'http://host/movie/$id.mp4',
      containerExtension: 'mp4',
      categoryId: category,
      rating: rating,
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

  test('kvGetIfFresh honours the max age', () async {
    await repo.kvPut('sourceType', 'xtream');
    expect(await repo.kvGet('sourceType'), 'xtream');
    expect(
      await repo.kvGetIfFresh('sourceType', const Duration(minutes: 5)),
      'xtream',
    );
    expect(
      await repo.kvGetIfFresh('sourceType', Duration.zero),
      isNull,
    );
  });

  group('CatalogImporter', () {
    late Directory tempDir;
    late PersistentJsonStore cacheStore;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('catalog_import_test');
      cacheStore = PersistentJsonStore(
        file: File('${tempDir.path}/cache.json'),
      );
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<void> seedLegacyBlob() async {
      await cacheStore.write('m3ue_cache_vodStreams', {
        'timestamp': DateTime(2026).toIso8601String(),
        'data': [encodeVod(_vod(1, 'Legacy Movie', category: 'a'))],
      });
      await cacheStore.write('m3ue_cache_vodCategories', {
        'timestamp': DateTime(2026).toIso8601String(),
        'data': [encodeCategory(const Category(id: 'a', name: 'Action'))],
      });
      await cacheStore.write('m3ue_cache_epgGuide', {
        'timestamp': DateTime(2026).toIso8601String(),
        'data': [
          encodeEpgProgram(
            EpgProgram(
              channelId: 'c1',
              title: 'Show',
              description: '',
              start: DateTime(2026, 1, 1, 20),
              end: DateTime(2026, 1, 1, 21),
            ),
          ),
        ],
      });
    }

    CatalogImporter importer() => CatalogImporter(
      repository: repo,
      cacheStore: cacheStore,
      sourceKey: 's1',
    );

    test(
      'imports the legacy blob into rows and deletes the source keys',
      () async {
        await seedLegacyBlob();

        expect(await importer().run(), isTrue);

        final items = await repo.allItems<VodItem>('s1', kCatalogKindVod);
        expect(items.single.name, 'Legacy Movie');
        expect(
          (await repo.allCategories('s1', kCatalogKindVod)).single.name,
          'Action',
        );
        expect(
          (await repo.programmesEndingAfter(DateTime(2000))).single.title,
          'Show',
        );

        final snapshot = await cacheStore.snapshot();
        expect(
          snapshot.keys.where((k) => k.startsWith('m3ue_cache_')),
          isEmpty,
        );
      },
    );

    test('is a no-op when nothing legacy is present', () async {
      expect(await importer().run(), isFalse);
    });

    test(
      'sweeps stragglers without re-importing when rows already exist',
      () async {
        await repo.replaceItems(
          sourceKey: 's1',
          kind: kCatalogKindVod,
          items: [_vod(99, 'Already here')],
        );
        await seedLegacyBlob();

        expect(await importer().run(), isFalse);

        final items = await repo.allItems<VodItem>('s1', kCatalogKindVod);
        expect(items.single.id, 99); // not overwritten by the legacy blob
        final snapshot = await cacheStore.snapshot();
        expect(
          snapshot.keys.where((k) => k.startsWith('m3ue_cache_')),
          isEmpty,
        );
      },
    );
  });
}
