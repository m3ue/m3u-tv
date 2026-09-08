import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PersistentJsonStore> newStore(String prefix) async {
    final directory = await Directory.systemTemp.createTemp(prefix);
    addTearDown(() => directory.delete(recursive: true));
    return PersistentJsonStore(file: File('${directory.path}/app_state.json'));
  }

  CatalogRepository newRepo() {
    final repo = CatalogRepository(CatalogDatabase.memory());
    addTearDown(repo.close);
    return repo;
  }

  test(
    'series metadata survives a persist + cold hydrate round trip',
    () async {
      final store = await newStore('m3u-tv-series-cache-roundtrip-');
      final repo = newRepo();
      final source = CacheService(store: store, catalogRepository: repo);
      final original = <Series>[
        const Series(
          id: 42,
          name: 'The Example',
          coverUrl: 'https://img/cover.jpg',
          backdropUrl: 'https://img/backdrop.jpg',
          categoryId: '7',
          categoryIds: ['7', '900000002'],
          plot: 'A plot.',
          rating: 4.3,
          tmdbId: 99123,
        ),
      ];
      await source.set<List<Series>>('seriesStreams', original);

      // A fresh CacheService with no memory forces hydration from SQLite.
      final hydrated = CacheService(store: store, catalogRepository: repo);
      final entry = await hydrated.get<List<Series>>('seriesStreams');
      final series = entry!.data.single;

      expect(series.id, 42);
      expect(series.name, 'The Example');
      expect(series.coverUrl, 'https://img/cover.jpg');
      expect(series.backdropUrl, 'https://img/backdrop.jpg');
      expect(series.categoryId, '7');
      expect(series.categoryIds, <String>['7', '900000002']);
      expect(series.plot, 'A plot.');
      expect(series.rating, 4.3);
      expect(series.tmdbId, 99123);
    },
  );

  test(
    'vod overlapping category_ids survive a persist + cold hydrate round trip',
    () async {
      final store = await newStore('m3u-tv-vod-cache-roundtrip-');
      final repo = newRepo();
      final source = CacheService(store: store, catalogRepository: repo);
      final original = <VodItem>[
        const VodItem(
          id: 7,
          name: 'Flow',
          streamUrl: 'http://example.com/7.mp4',
          containerExtension: 'mp4',
          categoryId: '357',
          categoryIds: ['357', '900000001'],
          rating: 4.1,
        ),
      ];
      await source.set<List<VodItem>>('vodStreams', original);

      final hydrated = CacheService(store: store, catalogRepository: repo);
      final entry = await hydrated.get<List<VodItem>>('vodStreams');
      final item = entry!.data.single;

      expect(item.categoryId, '357');
      expect(item.categoryIds, <String>['357', '900000001']);
    },
  );

  test(
    'epg guide programmes survive a persist + cold hydrate round trip',
    () async {
      final store = await newStore('m3u-tv-epg-guide-roundtrip-');
      final repo = newRepo();
      final source = CacheService(store: store, catalogRepository: repo);
      final start = DateTime.utc(2026, 7, 30, 12);
      final original = <EpgProgram>[
        EpgProgram(
          channelId: 'bbc.one',
          title: 'News at Noon',
          description: 'Bulletin',
          start: start,
          end: start.add(const Duration(minutes: 30)),
          subtitle: 'Lunchtime edition',
        ),
        EpgProgram(
          channelId: 'bbc.two',
          title: 'Afternoon Film',
          description: '',
          start: start.add(const Duration(minutes: 30)),
          end: start.add(const Duration(hours: 2)),
        ),
      ];
      await source.set<List<EpgProgram>>('epgGuide', original);

      final hydrated = CacheService(store: store, catalogRepository: repo);
      final entry = await hydrated.get<List<EpgProgram>>('epgGuide');
      final programs = entry!.data;

      expect(programs, hasLength(2));
      expect(programs[0].channelId, 'bbc.one');
      expect(programs[0].title, 'News at Noon');
      expect(programs[0].description, 'Bulletin');
      expect(programs[0].start, start);
      expect(programs[0].end, start.add(const Duration(minutes: 30)));
      expect(programs[0].subtitle, 'Lunchtime edition');
      expect(programs[1].channelId, 'bbc.two');
      expect(programs[1].subtitle, isNull);
    },
  );

  group('with a CatalogRepository', () {
    test(
      'catalog keys round-trip through SQLite, non-catalog keys do not',
      () async {
        final store = await newStore('m3u-tv-cache-repo-');
        final repo = newRepo();
        final cache = CacheService(store: store, catalogRepository: repo);

        await cache.replace(<String, Object?>{
          'sourceType': 'xtream',
          'vodStreams': <VodItem>[
            const VodItem(
              id: 5,
              name: 'Repo Movie',
              streamUrl: 'http://h/5.mp4',
              containerExtension: 'mp4',
              categoryId: 'c1',
            ),
          ],
          'vodCategories': const <Category>[Category(id: 'c1', name: 'Films')],
          'liveStreams': const <Channel>[],
          'liveCategories': const <Category>[],
          'seriesStreams': const <Series>[],
          'seriesCategories': const <Category>[],
          'epgGuide': const <EpgProgram>[],
        });

        // Catalog data comes back from a fresh CacheService (no shared memory).
        final fresh = CacheService(store: store, catalogRepository: repo);
        final vod = await fresh.get<List<VodItem>>('vodStreams');
        expect(vod!.data.single.name, 'Repo Movie');
        expect(vod.isStale, isFalse);
        expect(
          (await fresh.get<List<Category>>('vodCategories'))!.data.single.name,
          'Films',
        );

        // The catalog blob keys were never written to the JSON store.
        final snapshot = await store.snapshot();
        expect(snapshot.containsKey('m3ue_cache_vodStreams'), isFalse);
        expect(snapshot.containsKey('m3ue_cache_sourceType'), isTrue);
        expect(
          (await fresh.get<String>('sourceType'))!.data,
          'xtream',
        );
      },
    );

    test('staleness is derived from the stored write timestamp', () async {
      final store = await newStore('m3u-tv-cache-repo-stale-');
      final repo = newRepo();
      final cache = CacheService(
        store: store,
        catalogRepository: repo,
      );

      await cache.set<List<VodItem>>('vodStreams', const <VodItem>[]);
      expect((await cache.get<List<VodItem>>('vodStreams'))!.isStale, isFalse);

      // Backdate the timestamp row past the refresh interval.
      await repo.kvPut(
        '__ts_vodStreams',
        DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch
            .toString(),
      );
      expect((await cache.get<List<VodItem>>('vodStreams'))!.isStale, isTrue);
    });

    test('get returns null for a catalog key that was never written', () async {
      final store = await newStore('m3u-tv-cache-repo-empty-');
      final cache = CacheService(store: store, catalogRepository: newRepo());
      expect(await cache.get<List<VodItem>>('vodStreams'), isNull);
    });

    test('replace clears repo-backed keys the caller omitted', () async {
      final store = await newStore('m3u-tv-cache-repo-omit-');
      final repo = newRepo();
      final cache = CacheService(store: store, catalogRepository: repo);

      await cache.set<List<VodItem>>('vodStreams', const <VodItem>[
        VodItem(
          id: 1,
          name: 'Gone',
          streamUrl: 'http://h/1.mp4',
          containerExtension: 'mp4',
        ),
      ]);
      // A replace that doesn't mention vodStreams should wipe it.
      await cache.replace(<String, Object?>{'liveStreams': const <Channel>[]});

      expect(await cache.get<List<VodItem>>('vodStreams'), isNull);
    });

    test('snapshot + restore round-trips the SQLite catalog', () async {
      final store = await newStore('m3u-tv-cache-repo-snap-');
      final repo = newRepo();
      final cache = CacheService(store: store, catalogRepository: repo);

      await cache.set<List<VodItem>>('vodStreams', const <VodItem>[
        VodItem(
          id: 1,
          name: 'Original',
          streamUrl: 'http://h/1.mp4',
          containerExtension: 'mp4',
        ),
      ]);
      final snapshot = await cache.snapshot();

      await cache.set<List<VodItem>>('vodStreams', const <VodItem>[
        VodItem(
          id: 2,
          name: 'Replacement',
          streamUrl: 'http://h/2.mp4',
          containerExtension: 'mp4',
        ),
      ]);
      await cache.restore(snapshot);

      final restored = await cache.get<List<VodItem>>('vodStreams');
      expect(restored!.data.single.name, 'Original');
    });
  });
}
