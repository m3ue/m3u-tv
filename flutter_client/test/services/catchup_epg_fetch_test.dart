import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'catchup-test',
  password: 'catchup-pass',
);

const _catchupChannel = Channel(
  id: 101,
  name: 'Route News',
  streamUrl: 'https://example.com/news.m3u8',
  epgChannelId: 'news.epg',
  catchupSupported: true,
  catchupDays: 7,
);

const _plainChannel = Channel(
  id: 202,
  name: 'No Catchup',
  streamUrl: 'https://example.com/plain.m3u8',
  epgChannelId: 'plain.epg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ensureCatchupEpgForChannel fetches every day in the retention window and '
    'merges the returned programs',
    () async {
      final transport = _CatchupTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);
      transport.epgDates.clear();

      await controller.ensureCatchupEpgForChannel(_catchupChannel);

      // retentionDays (7) + the partial current day = 8 dated requests.
      expect(transport.epgDates, hasLength(8));
      final today = DateTime.now();
      final expectedStart = DateTime.utc(
        today.year,
        today.month,
        today.day - 7,
      );
      final expectedEnd = DateTime.utc(today.year, today.month, today.day);
      for (final raw in transport.epgDates) {
        final parsed = DateTime.parse('${raw}T00:00:00Z');
        expect(parsed.isBefore(expectedStart), isFalse, reason: raw);
        expect(parsed.isAfter(expectedEnd), isFalse, reason: raw);
      }
      expect(transport.epgDates.first, _ymd(expectedStart));
      expect(transport.epgDates.last, _ymd(expectedEnd));

      expect(
        controller.epgService
            .programsForChannel(_catchupChannel)
            .map((program) => program.title),
        contains('Catchup Fixture'),
      );
    },
  );

  test(
    'a second call within the cache TTL does not re-hit the server',
    () async {
      final transport = _CatchupTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);

      await controller.ensureCatchupEpgForChannel(_catchupChannel);
      transport.epgDates.clear();
      await controller.ensureCatchupEpgForChannel(_catchupChannel);

      expect(transport.epgDates, isEmpty);
    },
  );

  test(
    'evicting a channel schedule forgets its catchup fetch, so the next '
    'open fetches again',
    () async {
      final transport = _CatchupTransport();
      final epgService = EpgService(residentCapacity: 1);
      final controller = _controller(transport, epgService: epgService);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);
      await controller.ensureCatchupEpgForChannel(_catchupChannel);

      // Another channel's schedule becoming resident (a guide row scrolled
      // to a dated range) pushes this one out of memory.
      final now = DateTime.now().toUtc();
      epgService.mergePrograms(
        [
          EpgProgram(
            channelId: 'plain.epg',
            title: 'Other',
            description: '',
            start: now,
            end: now.add(const Duration(hours: 1)),
          ),
        ],
        channelIds: ['plain.epg'],
        replaceExisting: false,
        markFresh: false,
      );
      for (var i = 0; i < 4; i++) {
        await pumpEventQueue();
        await epgService.flushStore();
      }

      transport.epgDates.clear();
      await controller.ensureCatchupEpgForChannel(_catchupChannel);
      expect(transport.epgDates, isNotEmpty);
    },
  );

  test('channels without catchup never trigger a fetch', () async {
    final transport = _CatchupTransport();
    final controller = _controller(transport);
    addTearDown(controller.dispose);
    expect(await controller.connectXtream(_credentials), isTrue);
    transport.epgDates.clear();

    await controller.ensureCatchupEpgForChannel(_plainChannel);

    expect(transport.epgDates, isEmpty);
  });

  test('a failed fetch clears the memo so the next open retries', () async {
    final transport = _CatchupTransport()..failEpgBatch = true;
    final controller = _controller(transport);
    addTearDown(controller.dispose);
    expect(await controller.connectXtream(_credentials), isTrue);

    await controller.ensureCatchupEpgForChannel(_catchupChannel);
    expect(controller.epgService.programsForChannel(_catchupChannel), isEmpty);

    transport
      ..failEpgBatch = false
      ..epgDates.clear();
    await controller.ensureCatchupEpgForChannel(_catchupChannel);

    expect(transport.epgDates, isNotEmpty);
    expect(
      controller.epgService
          .programsForChannel(_catchupChannel)
          .map((program) => program.title),
      contains('Catchup Fixture'),
    );
  });

  test(
    'concurrent calls for the same channel collapse to a single fetch',
    () async {
      final transport = _CatchupTransport();
      final gate = Completer<void>();
      transport.beforeEpgBatch = gate.future;
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);
      transport.epgDates.clear();

      final first = controller.ensureCatchupEpgForChannel(_catchupChannel);
      final second = controller.ensureCatchupEpgForChannel(_catchupChannel);
      gate.complete();
      await Future.wait([first, second]);

      // One window fetch, not two: still just retentionDays + 1 dated requests.
      expect(transport.epgDates, hasLength(8));
    },
  );

  test(
    'a source reset clears the memo so a later open fetches again',
    () async {
      final transport = _CatchupTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_credentials), isTrue);
      await controller.ensureCatchupEpgForChannel(_catchupChannel);
      expect(transport.epgDates, isNotEmpty);

      await controller.disconnect();
      expect(await controller.connectXtream(_credentials), isTrue);
      transport.epgDates.clear();

      await controller.ensureCatchupEpgForChannel(_catchupChannel);

      expect(transport.epgDates, hasLength(8));
    },
  );

  test(
    'synthetic dummy- gap-fill programmes are filtered out of the merge',
    () async {
      final transport = _CatchupTransport()..includeDummyRow = true;
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);

      await controller.ensureCatchupEpgForChannel(_catchupChannel);

      final titles = controller.epgService
          .programsForChannel(_catchupChannel)
          .map((program) => program.title)
          .toSet();
      expect(titles, contains('Catchup Fixture'));
      // The dummy row is titled with the channel name - it must not survive.
      expect(titles, isNot(contains('Route News')));
    },
  );

  test(
    'a successful catchup fetch marks the channel fresh so a later default '
    'guide fetch will not replace the retention window back out',
    () async {
      final transport = _CatchupTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);

      expect(
        controller.epgService.hasFreshDataForChannel(_catchupChannel),
        isFalse,
      );

      await controller.ensureCatchupEpgForChannel(_catchupChannel);

      expect(
        controller.epgService.hasFreshDataForChannel(_catchupChannel),
        isTrue,
      );
    },
  );

  test(
    'a second concurrent open resolves only when the shared fetch does',
    () async {
      final transport = _CatchupTransport();
      final gate = Completer<void>();
      transport.beforeEpgBatch = gate.future;
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);

      final first = controller.ensureCatchupEpgForChannel(_catchupChannel);
      final second = controller.ensureCatchupEpgForChannel(_catchupChannel);
      var secondDone = false;
      unawaited(second.then((_) => secondDone = true));
      await pumpEventQueue();
      expect(secondDone, isFalse);

      gate.complete();
      await Future.wait([first, second]);
      expect(secondDone, isTrue);
    },
  );

  test(
    'a response that lands after a source switch is not merged into the new '
    'guide',
    () async {
      final transport = _CatchupTransport();
      final gate = Completer<void>();
      transport.beforeEpgBatch = gate.future;
      final controller = _controller(transport);
      addTearDown(controller.dispose);
      expect(await controller.connectXtream(_credentials), isTrue);

      final pending = controller.ensureCatchupEpgForChannel(_catchupChannel);
      await controller.disconnect();
      gate.complete();
      await pending;

      expect(
        controller.epgService.programsForChannel(_catchupChannel),
        isEmpty,
      );
    },
  );
}

String _ymd(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)}';
}

AppStateController _controller(
  _CatchupTransport transport, {
  EpgService? epgService,
}) {
  final memory = <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    epgService: epgService ?? EpgService(),
    favoritesService: FavoritesService(memory: memory),
    vodFavoritesService: FavoritesService(memory: memory, namespace: 'vod'),
    seriesFavoritesService: FavoritesService(
      memory: memory,
      namespace: 'series',
    ),
    aioFavoritesService: AIOStreamsFavoritesService(),
    resumeService: ResumeService(memory: memory),
    viewerService: ViewerService(memory: memory),
    tvNotificationService: _NotificationService(),
    tvNotificationStore: TvNotificationStore(memory: memory),
    reverbService: _NoopReverbService(),
  );
}

class _CatchupTransport {
  bool failEpgBatch = false;
  bool includeDummyRow = false;
  Future<void>? beforeEpgBatch;
  final List<String> epgDates = <String>[];

  Future<Object?> call(XtreamRequest request) async {
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'server_info': <String, Object?>{'timezone': 'UTC'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            'features': <String>['dvr'],
          },
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_recently_watched':
      case 'list_dvr_series_rules':
      case 'sync_favorites':
        return const <Object?>[];
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'ulid': 'viewer-admin',
            'name': 'Admin',
            'is_admin': true,
          },
        ];
      case 'get_dvr_recordings':
        return const <Object?>[];
      case 'get_dvr_storage':
        return <String, Object?>{
          'used_bytes': 0,
          'quota_bytes': null,
          'percent_used': null,
          'recording_count': 0,
          'scope': 'account',
        };
      case 'get_epg_batch':
        final date = request.params['date'];
        if (date == null) return const <String, Object?>{};
        await beforeEpgBatch;
        if (failEpgBatch) throw StateError('epg batch boom');
        epgDates.add(date);
        final start = DateTime.parse('${date}T09:00:00Z');
        return <String, Object?>{
          '101': <Map<String, Object?>>[
            if (includeDummyRow)
              <String, Object?>{
                'id': 'dummy-${date.replaceAll('-', '')}',
                'stream_id': 101,
                'title': 'Route News',
                'description': 'No information available',
                'start': start
                    .subtract(const Duration(hours: 1))
                    .toIso8601String(),
                'end': start.toIso8601String(),
              },
            <String, Object?>{
              'id': 'real-${date.replaceAll('-', '')}',
              'stream_id': 101,
              'title': 'Catchup Fixture',
              'description': 'Fixture',
              'start': start.toIso8601String(),
              'end': start.add(const Duration(minutes: 30)).toIso8601String(),
            },
          ],
        };
      default:
        throw StateError('No fixture for ${request.action}');
    }
  }
}

class _NotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => const (
    TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: false,
      channelName: '',
      reverb: ReverbConfig(host: '', port: 0, scheme: 'wss', appKey: ''),
    ),
    <TvNotificationItem>[],
  );
}

class _NoopReverbService extends ReverbService {
  @override
  Future<void> disconnect() async {}
}
