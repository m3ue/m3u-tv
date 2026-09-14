import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PersistentJsonStore> newStore(String prefix) async {
    final directory = await Directory.systemTemp.createTemp(prefix);
    addTearDown(() => directory.delete(recursive: true));
    return PersistentJsonStore(file: File('${directory.path}/app_state.json'));
  }

  test(
    'series metadata survives a persist + cold hydrate round trip',
    () async {
      final store = await newStore('m3u-tv-series-cache-roundtrip-');
      final source = CacheService(store: store);
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

      // A fresh CacheService with no memory forces hydration from the store.
      final hydrated = CacheService(store: store);
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
      final source = CacheService(store: store);
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

      final hydrated = CacheService(store: store);
      final entry = await hydrated.get<List<VodItem>>('vodStreams');
      final item = entry!.data.single;

      expect(item.categoryId, '357');
      expect(item.categoryIds, <String>['357', '900000001']);
    },
  );

  test('legacy rating_5based cache entries still hydrate a rating', () async {
    final store = await newStore('m3u-tv-series-cache-legacy-');
    await store.write('m3ue_cache_seriesStreams', <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'data': <Object?>[
        <String, Object?>{
          'series_id': 1,
          'name': 'Legacy Series',
          'rating_5based': 3.5,
        },
      ],
    });

    final cache = CacheService(store: store);
    final entry = await cache.get<List<Series>>('seriesStreams');
    final series = entry!.data.single;

    expect(series.rating, 3.5);
    expect(series.backdropUrl, isNull);
    expect(series.tmdbId, isNull);
  });

  test(
    'a large live-stream catalog still hydrates correctly off the main '
    'isolate',
    () async {
      // Exercises the Isolate.run offload path in
      // _decodeCacheDataMaybeOffloaded (cache_service.dart), which only
      // kicks in at _decodeOffloadItemThreshold (256) entries or more - a
      // small list like the other tests here would just take the inline
      // path and never touch this code.
      final store = await newStore('m3u-tv-large-live-cache-roundtrip-');
      final source = CacheService(store: store);
      final original = List<Channel>.generate(
        300,
        (index) => Channel(
          id: index,
          name: 'Channel $index',
          streamUrl: 'http://example.com/$index',
          logoUrl: index.isEven ? 'http://example.com/$index.png' : null,
          categoryId: '${index % 5}',
          catchupSupported: index.isEven,
          catchupDays: index.isEven ? 7 : null,
        ),
      );
      await source.set<List<Channel>>('liveStreams', original);

      final hydrated = CacheService(store: store);
      final entry = await hydrated.get<List<Channel>>('liveStreams');
      final channels = entry!.data;

      expect(channels, hasLength(300));
      expect(channels[0].id, 0);
      expect(channels[0].name, 'Channel 0');
      expect(channels[0].logoUrl, 'http://example.com/0.png');
      expect(channels[0].catchupSupported, isTrue);
      expect(channels[0].catchupDays, 7);
      expect(channels[1].logoUrl, isNull);
      expect(channels[1].catchupSupported, isFalse);
      expect(channels[299].id, 299);
      expect(channels[299].categoryId, '4');
    },
  );

  test(
    'epg guide programmes survive a persist + cold hydrate round trip',
    () async {
      final store = await newStore('m3u-tv-epg-guide-roundtrip-');
      final source = CacheService(store: store);
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

      final hydrated = CacheService(store: store);
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
}
