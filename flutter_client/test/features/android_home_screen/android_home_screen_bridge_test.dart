import 'dart:ui';

import 'package:clock/clock.dart' as clock_package;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/android_home_screen/android_home_screen_bridge.dart';
import 'package:m3u_tv/features/carplay/car_catalog.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/channel_context.dart';
import 'package:m3u_tv/shared/channel_sort.dart';

final _now = DateTime.utc(2026, 11, 27, 20, 15);

class _FakeRepository extends Fake implements CatalogRepository {
  _FakeRepository(this.items, {this.lineup = const []});

  final Map<int, Object> items;

  /// The live channels, in provider order.
  final List<Channel> lineup;
  CatalogSort? lastSort;
  Set<int>? lastFavoritesFirst;

  @override
  Future<List<T>> pageActiveItems<T>({
    required String kind,
    String? categoryId,
    String? search,
    Set<int>? ids,
    CatalogSort sort = CatalogSort.providerOrder,
    Set<int> favoritesFirst = const {},
    required int offset,
    required int limit,
  }) async {
    lastSort = sort;
    lastFavoritesFirst = favoritesFirst;
    final ordered = [
      ...lineup.where((c) => favoritesFirst.contains(c.id)),
      ...lineup.where((c) => !favoritesFirst.contains(c.id)),
    ];
    return ordered.skip(offset).take(limit).cast<T>().toList();
  }

  @override
  Future<int> countActiveItems({
    required String kind,
    String? categoryId,
    String? search,
    Set<int>? ids,
  }) async => lineup.length;

  @override
  Future<List<T>> activeItemsByIds<T>({
    required String kind,
    required Set<int> ids,
  }) async => [
    for (final id in ids)
      if (items[id] case final T item) item,
  ];
}

class _FakeAppState extends Fake implements AppStateController {
  _FakeAppState({
    required this.progressList,
    required this.epgService,
    required this.catalogRepository,
  });

  @override
  List<Progress> progressList;
  @override
  final EpgService epgService;
  @override
  final CatalogRepository catalogRepository;
  @override
  final ViewSettingsService viewSettingsService = ViewSettingsService();
  @override
  final FavoritesService favoritesService = FavoritesService();
  @override
  SportsCapability? get sportsCapability => null;
  @override
  bool isConfigured = true;
  @override
  bool get isBootstrapping => false;
  @override
  Viewer? get activeViewer => null;

  int refreshes = 0;
  final epgRequests = <List<Channel>>[];

  @override
  Future<void> ensureBooted() async {}
  @override
  Future<void> refreshRecentlyWatched() async => refreshes++;
  @override
  Future<bool> ensureServerHandshake() async {
    handshakes++;
    return true;
  }

  int handshakes = 0;
  @override
  void ensureEpgForChannels(
    List<Channel> channels, {
    DateTime? startDate,
    DateTime? endDate,
  }) => epgRequests.add(channels);
}

class _FakeCatalog extends CarCatalog {
  _FakeCatalog(_FakeAppState super.appState, this.channels);

  final List<Channel> channels;

  @override
  Future<Channel?> channelById(int id) async =>
      channels.where((c) => c.id == id).firstOrNull;

  @override
  AppLocalizations get l10n => lookupAppLocalizations(const Locale('en'));
}

const _news = Channel(
  id: 7,
  name: 'News 24',
  streamUrl: 'http://example.test/7.ts',
  logoUrl: 'http://example.test/7.png',
  epgChannelId: 'news.24',
);
const _sport = Channel(
  id: 8,
  name: 'Sport One',
  streamUrl: 'http://example.test/8.ts',
  epgChannelId: 'sport.one',
);

Progress _progress({
  required ContentType type,
  required int streamId,
  int position = 600,
  int? duration = 3600,
  bool completed = false,
  bool upNext = false,
  int? seriesId,
  String? title,
  String? seriesName,
  String? aioItemId,
}) => Progress(
  viewerId: 'viewer',
  contentType: type,
  streamId: streamId,
  positionSeconds: position,
  durationSeconds: duration,
  completed: completed,
  upNext: upNext,
  seriesId: seriesId,
  seasonNumber: seriesId == null ? null : 2,
  episodeNumber: seriesId == null ? null : 5,
  title: title,
  episodeTitle: seriesId == null ? null : 'The One',
  seriesName: seriesName,
  backdropUrl: 'http://example.test/$streamId.jpg',
  aioItemId: aioItemId,
);

void main() {
  late _FakeAppState appState;
  late AndroidHomeScreenBridge bridge;

  setUp(() {
    final epg = EpgService(clock: () => _now)
      ..loadPrograms([
        EpgProgram(
          channelId: 'news.24',
          title: 'Evening News',
          description: '',
          start: _now.subtract(const Duration(minutes: 15)),
          end: _now.add(const Duration(minutes: 45)),
          backdropUrl: 'http://example.test/news.jpg',
        ),
      ]);
    appState = _FakeAppState(
      progressList: [
        _progress(type: ContentType.vod, streamId: 1, title: 'A Movie'),
        _progress(type: ContentType.live, streamId: 2, title: 'Live'),
        _progress(
          type: ContentType.vod,
          streamId: 3,
          title: 'Finished',
          completed: true,
        ),
        _progress(
          type: ContentType.episode,
          streamId: 4,
          position: 0,
          upNext: true,
          seriesId: 40,
          seriesName: 'A Show',
        ),
        _progress(
          type: ContentType.vod,
          streamId: 5,
          title: 'From AIOStreams',
          aioItemId: 'tt1',
        ),
      ],
      epgService: epg,
      catalogRepository: _FakeRepository({}, lineup: const [_news, _sport]),
    );
    bridge = AndroidHomeScreenBridge(
      _FakeCatalog(appState, const [_news, _sport]),
      channel: const MethodChannel('test/home_screen'),
      supported: Future.value(true),
      guideWait: Duration.zero,
    );
  });

  test('Watch Next holds Continue Watching and Up Next only', () async {
    final payload = await clock_package.withClock(
      clock_package.Clock.fixed(_now),
      () => bridge.collect(fresh: false),
    );
    final items = payload['watchNext']! as List<Map<String, Object?>>;
    expect(items.map((i) => i['key']), ['vod:1', 'episode:4']);

    final movie = items[0];
    expect(movie['title'], 'A Movie');
    expect(movie['positionMs'], 600000);
    expect(movie['durationMs'], 3600000);
    expect(movie['upNext'], false);
    expect(movie['engagement'], '600');
    expect(movie['imageUrl'], 'http://example.test/1.jpg');

    final episode = items[1];
    expect(episode['title'], 'A Show');
    expect(episode['episodeTitle'], 'The One');
    expect(episode['seasonNumber'], 2);
    expect(episode['upNext'], true);
    expect(episode['engagement'], 'next');
    expect(episode.containsKey('positionMs'), isFalse);
    expect(episode['launch'], containsPair('seriesId', 40));
  });

  List<Map<String, Object?>> channelItems(
    Map<String, Object?> payload,
    String id,
  ) =>
      (payload['channels']! as List<Map<String, Object?>>).firstWhere(
            (channel) => channel['id'] == id,
          )['items']!
          as List<Map<String, Object?>>;

  test('On Now lists the Live TV lineup with what is airing', () async {
    final payload = await clock_package.withClock(
      clock_package.Clock.fixed(_now),
      () => bridge.collect(fresh: false),
    );
    final channels = payload['channels']! as List<Map<String, Object?>>;
    expect(
      channels.firstWhere((c) => c['id'] == 'on_now')['title'],
      'On Now',
    );
    final items = channelItems(payload, 'on_now');
    expect(items, hasLength(2));

    final news = items[0];
    expect(news['key'], 'live:7');
    expect(news['title'], 'Evening News');
    expect(news['description'], startsWith('News 24 · '));
    expect(news['artworkUrl'], 'http://example.test/news.jpg');
    expect(news['live'], true);
    expect(news['launch'], {'kind': 'live', 'channelId': 7});

    // No guide: the channel's name, and no times.
    final sport = items[1];
    expect(sport['title'], 'Sport One');
    expect(sport.containsKey('startMs'), isFalse);

    expect(
      payload['refreshAtMs'],
      _now.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
    );
  });

  test(
    'On Now follows the Live TV sort; favorites order, never filter',
    () async {
      final settings = appState.viewSettingsService;
      await settings.setRememberMediaSort(true);
      await settings.setLiveTvSortOption(ChannelSortOption.alphabeticalAsc);
      await settings.setLiveTvFavoritesFirst(true);
      await appState.favoritesService.toggle(_sport.id);
      final repository = appState.catalogRepository as _FakeRepository;

      var payload = await bridge.collect(fresh: false);
      expect(
        repository.lastSort,
        catalogSortForChannels(ChannelSortOption.alphabeticalAsc),
      );
      expect(repository.lastFavoritesFirst, {_sport.id});
      expect(channelItems(payload, 'on_now').map((i) => i['key']), [
        'live:8',
        'live:7',
      ]);

      await settings.setLiveTvFavoritesFirst(false);
      payload = await bridge.collect(fresh: false);
      expect(repository.lastFavoritesFirst, isEmpty);
      expect(channelItems(payload, 'on_now').map((i) => i['key']), [
        'live:7',
        'live:8',
      ]);
    },
  );

  test('Watch Next fills to 10 past entries that resolve to nothing', () async {
    appState.progressList = [
      // No title and no catalog entry: dropped.
      _progress(type: ContentType.vod, streamId: 100),
      for (var id = 101; id <= 112; id++)
        _progress(type: ContentType.vod, streamId: id, title: 'Movie $id'),
    ];
    final payload = await bridge.collect(fresh: false);
    final items = payload['watchNext']! as List<Map<String, Object?>>;
    expect(items, hasLength(AndroidHomeScreenBridge.maxWatchNext));
    expect(items.first['key'], 'vod:101');
  });

  test('the Continue Watching row lists the Watch Next cards', () async {
    final payload = await bridge.collect(fresh: false);
    final watchNext = payload['watchNext']! as List<Map<String, Object?>>;
    final row = channelItems(payload, 'continue_watching');
    expect(row.map((i) => i['key']), watchNext.map((i) => i['key']));

    final movie = row[0];
    expect(movie['title'], 'A Movie');
    expect(movie['artworkUrl'], 'http://example.test/1.jpg');
    expect(movie['positionMs'], 600000);
    expect(movie['durationMs'], 3600000);
    expect(movie['launch'], watchNext[0]['launch']);

    final upNext = row[1];
    expect(upNext['description'], 'Up next');
    expect(upNext['episodeTitle'], 'The One');
    expect(upNext.containsKey('positionMs'), isFalse);
  });

  test('Sports is empty without the server Sports feature', () async {
    final payload = await bridge.collect(fresh: false);
    final sports = (payload['channels']! as List<Map<String, Object?>>)
        .firstWhere((channel) => channel['id'] == 'sports');
    expect(sports['enabled'], true);
    expect(sports['items'], isEmpty);
  });

  test('turned off rows are sent empty', () async {
    await appState.viewSettingsService.setAndroidHomeWatchNext(false);
    await appState.viewSettingsService.setAndroidHomeOnNow(false);
    await appState.viewSettingsService.setAndroidHomeSports(false);
    final payload = await bridge.collect(fresh: false);
    expect(payload['watchNextEnabled'], false);
    expect(payload['watchNext'], isEmpty);
    for (final channel in payload['channels']! as List<Map<String, Object?>>) {
      expect(channel['enabled'], false);
      expect(channel['items'], isEmpty);
    }
    expect(payload.containsKey('refreshAtMs'), isFalse);
  });

  test(
    'a background refresh re-reads Continue Watching and the guide',
    () async {
      await bridge.collect(fresh: true);
      expect(appState.refreshes, 1);
      expect(appState.epgRequests.single, [_news, _sport]);
      expect(appState.handshakes, 1);
    },
  );

  test('collect leaves the rows alone when signed out', () async {
    appState.isConfigured = false;
    expect(await bridge.handle(const MethodCall('collect')), isNull);
  });

  test('a Watch Next card resumes its Continue Watching entry', () async {
    final launch = await bridge.resolveLaunch({
      'kind': 'progress',
      'contentType': 'vod',
      'streamId': 1,
      'positionSeconds': 600,
      'upNext': 0,
    });
    expect(
      (launch! as HomeScreenProgressLaunch).progress,
      same(appState.progressList.first),
    );
  });

  test('a card whose entry has left Continue Watching still opens', () async {
    final launch = await bridge.resolveLaunch({
      'kind': 'progress',
      'contentType': 'episode',
      'streamId': 99,
      'positionSeconds': 120,
      'seriesId': 40,
      'upNext': 0,
    });
    final progress = (launch! as HomeScreenProgressLaunch).progress;
    expect(progress.contentType, ContentType.episode);
    expect(progress.streamId, 99);
    expect(progress.positionSeconds, 120);
    expect(progress.seriesId, 40);
  });

  test('an On Now card plays the channel within the lineup', () async {
    final launch = await bridge.resolveLaunch({
      'kind': 'live',
      'channelId': 8,
    });
    final channelLaunch = launch! as HomeScreenChannelLaunch;
    expect(channelLaunch.channel, same(_sport));
    expect(channelLaunch.context, isA<CatalogChannelContext>());
    expect(channelLaunch.context.length, 2);
    expect(
      await bridge.resolveLaunch({'kind': 'live', 'channelId': 1}),
      isNull,
    );
  });
}
