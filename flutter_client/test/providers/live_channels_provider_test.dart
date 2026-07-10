import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

const _stubChannel = Channel(
  id: 1,
  name: 'BBC One',
  streamUrl: 'http://example.com/bbc1.m3u8',
);

class _StubXtreamService extends XtreamService {
  _StubXtreamService({
    this.channels = const [],
    this.configured = false,
    this.delay = Duration.zero,
  }) : super(cache: CacheService());

  final List<Channel> channels;
  final Duration delay;
  bool configured;
  int fetchCount = 0;

  @override
  bool get isConfigured => configured;

  @override
  Future<List<Channel>> getLiveStreams({String? categoryId}) async {
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    fetchCount++;
    return channels;
  }
}

AppStateController _buildController({
  CacheService? cache,
  _StubXtreamService? xtream,
}) {
  final resolvedCache = cache ?? CacheService();
  final resolvedXtream =
      xtream ?? _StubXtreamService(channels: const [_stubChannel]);
  return AppStateController(
    cacheService: resolvedCache,
    xtreamService: resolvedXtream,
  );
}

ProviderContainer _container(AppStateController controller) {
  return ProviderContainer(overrides: [overrideAppState(controller)]);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('liveChannelsProvider (bridge)', () {
    test('reflects channels list from AppStateController synchronously', () {
      final container = _container(_buildController());
      addTearDown(container.dispose);

      expect(container.read(liveChannelsProvider), isEmpty);
    });
  });

  group('LiveChannelsNotifier', () {
    test('returns empty list when not configured and cache is cold', () async {
      final cache = CacheService();
      final stub = _StubXtreamService();
      final container = _container(
        _buildController(cache: cache, xtream: stub),
      );
      addTearDown(container.dispose);

      final result = await container.read(liveChannelsNotifierProvider.future);

      expect(result, isEmpty);
      expect(stub.fetchCount, 0);
    });

    test(
      'returns cached data without network call when cache is fresh',
      () async {
        final cache = CacheService();
        final stub = _StubXtreamService(
          channels: const [_stubChannel],
          configured: true,
        );

        await cache.set<List<Channel>>('liveStreams', const [_stubChannel]);

        final container = _container(
          _buildController(cache: cache, xtream: stub),
        );
        addTearDown(container.dispose);

        final result = await container.read(
          liveChannelsNotifierProvider.future,
        );

        expect(result, hasLength(1));
        expect(result.first.name, 'BBC One');
        expect(stub.fetchCount, 0);
      },
    );

    test('fetches from network when cache is stale', () async {
      final cache = CacheService(
        refreshInterval: Duration.zero, // everything is immediately stale
      );
      final stub = _StubXtreamService(
        channels: const [_stubChannel],
        configured: true,
      );

      await cache.set<List<Channel>>('liveStreams', const []);

      final container = _container(
        _buildController(cache: cache, xtream: stub),
      );
      addTearDown(container.dispose);

      final result = await container.read(liveChannelsNotifierProvider.future);

      expect(result, hasLength(1));
      expect(stub.fetchCount, 1);
    });

    test('refresh(clearCache: true) forces a fresh network fetch', () async {
      final cache = CacheService();
      final stub = _StubXtreamService(
        channels: const [_stubChannel],
        configured: true,
      );

      await cache.set<List<Channel>>('liveStreams', const [_stubChannel]);

      final container = _container(
        _buildController(cache: cache, xtream: stub),
      );
      addTearDown(container.dispose);

      // First read — served from fresh cache.
      await container.read(liveChannelsNotifierProvider.future);
      expect(stub.fetchCount, 0);

      await container
          .read(liveChannelsNotifierProvider.notifier)
          .refresh(clearCache: true);

      expect(stub.fetchCount, 1);
    });

    test('concurrent reads deduplicate into a single fetch', () async {
      final cache = CacheService(refreshInterval: Duration.zero);
      final stub = _StubXtreamService(
        channels: const [_stubChannel],
        configured: true,
        delay: const Duration(milliseconds: 10),
      );

      final container = _container(
        _buildController(cache: cache, xtream: stub),
      );
      addTearDown(container.dispose);

      final results = await Future.wait([
        container.read(liveChannelsNotifierProvider.future),
        container.read(liveChannelsNotifierProvider.future),
        container.read(liveChannelsNotifierProvider.future),
      ]);

      expect(results.every((r) => r.length == 1), isTrue);
      expect(stub.fetchCount, 1);
    });
  });
}
