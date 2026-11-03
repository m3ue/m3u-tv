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
          iconUrl: 'https://images.example/noon.jpg',
          posterUrl: 'https://images.example/noon-poster.jpg',
          backdropUrl: 'https://images.example/noon-backdrop.jpg',
          category: 'News',
          rating: 'TV-G',
          season: 3,
          episode: 12,
          year: 2026,
          isNew: true,
          isPremiere: true,
          isRepeat: true,
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
      expect(programs[0].iconUrl, 'https://images.example/noon.jpg');
      expect(
        programs[0].posterUrl,
        'https://images.example/noon-poster.jpg',
      );
      expect(
        programs[0].backdropUrl,
        'https://images.example/noon-backdrop.jpg',
      );
      expect(programs[0].category, 'News');
      expect(programs[0].rating, 'TV-G');
      expect(programs[0].season, 3);
      expect(programs[0].episode, 12);
      expect(programs[0].year, 2026);
      expect(programs[0].isNew, isTrue);
      expect(programs[0].isPremiere, isTrue);
      expect(programs[0].isRepeat, isTrue);
      expect(programs[0].isPlaceholder, isFalse);
      expect(programs[1].channelId, 'bbc.two');
      expect(programs[1].subtitle, isNull);
      expect(programs[1].iconUrl, isNull);
      expect(programs[1].backdropUrl, isNull);
      expect(programs[1].isNew, isFalse);
    },
  );

  test(
    'itemCount is null until written, then counts without decoding',
    () async {
      final cache = CacheService(catalogRepository: newRepo());
      expect(await cache.itemCount('vodStreams'), isNull);
      await cache.set<List<VodItem>>('vodStreams', const [
        VodItem(id: 1, name: 'One', streamUrl: 'u1', containerExtension: 'mp4'),
        VodItem(id: 2, name: 'Two', streamUrl: 'u2', containerExtension: 'mp4'),
      ]);
      expect(await cache.itemCount('vodStreams'), 2);
      expect(await cache.itemCount('seriesStreams'), isNull);
    },
  );

  test('catalogKeys lists only the SQLite-backed blobs, not the scalars', () {
    expect(
      CacheService.catalogKeys.toSet(),
      <String>{
        'liveStreams',
        'vodStreams',
        'seriesStreams',
        'liveCategories',
        'vodCategories',
        'seriesCategories',
        'epgGuide',
      },
    );
    // `sourceType` lives in the JSON store, and a `viewers` list stored there
    // before each playlist kept its own is adopted at boot; `main`'s legacy
    // purge keys off this list, so they must not appear here.
    expect(CacheService.catalogKeys, isNot(contains('sourceType')));
    expect(CacheService.catalogKeys, isNot(contains('viewers')));
  });

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

      // Backdate the marker row past the refresh interval.
      await repo.kvPut(
        '__ts_vodStreams',
        '',
        updatedAtMs: DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
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

    VodItem movie(int id, String name) => VodItem(
      id: id,
      name: name,
      streamUrl: 'http://h/$id.mp4',
      containerExtension: 'mp4',
    );

    test('snapshot + restore round-trips the small keys only', () async {
      final store = await newStore('m3u-tv-cache-repo-snap-');
      final repo = newRepo();
      final cache = CacheService(store: store, catalogRepository: repo);

      await cache.set<String>('sourceType', 'xtream');
      await cache.set<List<VodItem>>('vodStreams', [movie(1, 'Original')]);
      final snapshot = await cache.snapshot();

      await cache.set<String>('sourceType', 'other');
      await cache.set<List<VodItem>>('vodStreams', [movie(2, 'Replacement')]);
      await cache.restore(snapshot);

      expect((await cache.get<String>('sourceType'))!.data, 'xtream');
      // Catalog rows need no snapshot (each playlist's are kept apart), so a
      // restore leaves them as they are.
      expect(
        (await cache.get<List<VodItem>>('vodStreams'))!.data.single.name,
        'Replacement',
      );
    });

    test('a load for another playlist leaves the shown one alone', () async {
      final repo = newRepo()..shownSource = 'playlist-a';
      final cache = CacheService(catalogRepository: repo);
      await cache.replace(<String, Object?>{
        'vodStreams': [movie(1, 'A movie')],
      });

      await cache.replace(<String, Object?>{
        'vodStreams': [movie(2, 'B movie')],
      }, sourceKey: 'playlist-b');

      expect(
        (await cache.get<List<VodItem>>('vodStreams'))!.data.single.name,
        'A movie',
      );
      repo.shownSource = 'playlist-b';
      expect(
        (await cache.get<List<VodItem>>('vodStreams'))!.data.single.name,
        'B movie',
      );
      expect(await cache.storedCatalogSources(), {'playlist-a', 'playlist-b'});
    });

    test('a catalog moves and drops with its write times', () async {
      final repo = newRepo();
      final cache = CacheService(catalogRepository: repo);
      // Rows cached before each playlist had its own.
      await cache.replace(<String, Object?>{
        'liveStreams': const <Channel>[],
        'vodStreams': [movie(1, 'Cached')],
      });
      final written = await cache.catalogUpdatedAt(
        CatalogRepository.defaultSource,
      );

      await cache.moveCatalog(CatalogRepository.defaultSource, 'playlist-a');

      expect(await cache.get<List<VodItem>>('vodStreams'), isNull);
      expect(await cache.catalogUpdatedAt('playlist-a'), written);
      repo.shownSource = 'playlist-a';
      expect(
        (await cache.get<List<VodItem>>('vodStreams'))!.data.single.name,
        'Cached',
      );

      await cache.dropCatalog('playlist-a');

      expect(await cache.get<List<VodItem>>('vodStreams'), isNull);
      expect(await cache.catalogUpdatedAt('playlist-a'), isNull);
      expect(await cache.storedCatalogSources(), isEmpty);
    });

    test('each playlist keeps its own viewers', () async {
      final store = await newStore('m3u-tv-cache-viewers-');
      final repo = newRepo()..shownSource = 'playlist-a';
      final cache = CacheService(store: store, catalogRepository: repo);
      const viewerA = Viewer(id: 1, ulid: 'viewer-a', name: 'A', isAdmin: true);
      const viewerB = Viewer(id: 2, ulid: 'viewer-b', name: 'B', isAdmin: true);
      await cache.replace(<String, Object?>{
        'viewers': const [viewerA],
      });
      await cache.replace(<String, Object?>{
        'viewers': const [viewerB],
      }, sourceKey: 'playlist-b');

      Future<List<String>> ulids({String? sourceKey}) async => [
        for (final viewer
            in (await cache.get<List<Viewer>>(
                  'viewers',
                  sourceKey: sourceKey,
                ))?.data ??
                const <Viewer>[])
          viewer.ulid,
      ];
      expect(await ulids(), ['viewer-a']);
      expect(await ulids(sourceKey: 'playlist-b'), ['viewer-b']);
      expect(
        (await store.snapshot()).keys,
        isNot(contains('m3ue_cache_viewers')),
      );

      // moveCatalog only moves a source with lists stored.
      await cache.moveCatalog('playlist-b', 'playlist-c');
      expect(await ulids(sourceKey: 'playlist-c'), isEmpty);
      await cache.replace(<String, Object?>{
        'liveStreams': const <Channel>[],
        'viewers': const [viewerB],
      }, sourceKey: 'playlist-b');
      await cache.moveCatalog('playlist-b', 'playlist-c');
      expect(await ulids(sourceKey: 'playlist-b'), isEmpty);
      expect(await ulids(sourceKey: 'playlist-c'), ['viewer-b']);

      await cache.dropCatalog('playlist-c');
      expect(await ulids(sourceKey: 'playlist-c'), isEmpty);
      expect(await ulids(), ['viewer-a']);
    });

    test(
      'viewers stored before playlists kept their own are adopted',
      () async {
        final store = await newStore('m3u-tv-cache-shared-viewers-');
        await store.write('m3ue_cache_viewers', <String, Object?>{
          'timestamp': DateTime.now().toIso8601String(),
          'data': [
            const Viewer(
              id: 1,
              ulid: 'viewer-a',
              name: 'A',
              isAdmin: true,
            ).toJson(),
          ],
        });
        final repo = newRepo()..shownSource = 'playlist-a';
        final cache = CacheService(store: store, catalogRepository: repo);

        await cache.adoptSharedViewers('playlist-a');

        final viewers = await cache.get<List<Viewer>>('viewers');
        expect(viewers!.data.single.ulid, 'viewer-a');
        expect(
          (await store.snapshot()).keys,
          isNot(contains('m3ue_cache_viewers')),
        );
        // Only once: a later call finds nothing to adopt.
        await cache.adoptSharedViewers('playlist-b');
        expect(
          await cache.get<List<Viewer>>('viewers', sourceKey: 'playlist-b'),
          isNull,
        );
      },
    );
  });
}
