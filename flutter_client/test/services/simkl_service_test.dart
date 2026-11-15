import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/simkl_service.dart';

void main() {
  const accessKey = 'simkl_access_token';
  const refreshKey = 'simkl_refresh_token';
  const expiryKey = 'simkl_token_expiry';

  String futureExpiry() =>
      '${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400}';

  SimklResponse deviceCode() => const SimklResponse(200, {
    'device_code': 'device-secret',
    'user_code': 'BDWP-HQPK',
    'verification_uri': 'https://simkl.com/pin',
    'verification_uri_complete': 'https://simkl.com/pin?user_code=BDWP-HQPK',
    'expires_in': 900,
    'interval': 3600,
  });

  SimklResponse tokens() => const SimklResponse(200, {
    'access_token': 'simkl_at_new',
    'refresh_token': 'simkl_rt_new',
    'expires_in': 604800,
    'scope': 'media:read media:write',
  });

  Future<SimklService> connected(
    _FakeTransport transport,
    InMemorySecureStorage storage, {
    Duration writeLockRetryDelay = Duration.zero,
  }) async {
    await storage.write(accessKey, 'simkl_at_old');
    await storage.write(refreshKey, 'simkl_rt_old');
    await storage.write(expiryKey, futureExpiry());
    final service = SimklService(
      storage: storage,
      clientId: 'client',
      transport: transport.call,
      writeLockRetryDelay: writeLockRetryDelay,
    );
    await service.init();
    return service;
  }

  group('device login', () {
    test('is unavailable without a client id', () async {
      final transport = _FakeTransport([]);
      final service = SimklService(
        storage: InMemorySecureStorage(),
        clientId: '',
        transport: transport.call,
      );
      addTearDown(service.dispose);

      expect(service.isConfigured, isFalse);
      await service.startDeviceAuth();

      expect(transport.requests, isEmpty);
      expect(service.status, SimklAuthStatus.disconnected);
    });

    test('requests a code, publishes it, and never sends a secret', () async {
      final transport = _FakeTransport([deviceCode()]);
      final service = SimklService(
        storage: InMemorySecureStorage(),
        clientId: 'client',
        transport: transport.call,
      );
      addTearDown(service.dispose);

      await service.startDeviceAuth();

      expect(service.status, SimklAuthStatus.pending);
      expect(service.pending?.userCode, 'BDWP-HQPK');
      expect(
        service.pending?.completeUrl,
        'https://simkl.com/pin?user_code=BDWP-HQPK',
      );
      final request = transport.requests.single;
      expect(request.path, '/oauth2/device');
      expect(request.form?['client_id'], 'client');
      expect(request.form?['scope'], 'media:read media:write');
      expect(request.form, isNot(contains('client_secret')));
    });

    test('keeps polling while pending and slows down on request', () async {
      final transport = _FakeTransport([
        deviceCode(),
        const SimklResponse(400, {'error': 'authorization_pending'}),
        const SimklResponse(400, {'error': 'slow_down'}),
      ]);
      final service = SimklService(
        storage: InMemorySecureStorage(),
        clientId: 'client',
        transport: transport.call,
      );
      addTearDown(service.dispose);
      await service.startDeviceAuth();
      final interval = service.pollIntervalForTesting;

      await service.pollForTesting();
      expect(service.status, SimklAuthStatus.pending);
      expect(service.pollIntervalForTesting, interval);

      await service.pollForTesting();
      expect(service.status, SimklAuthStatus.pending);
      expect(
        service.pollIntervalForTesting,
        interval + const Duration(seconds: 5),
      );
    });

    test('a network failure while polling keeps the code on screen', () async {
      final transport = _FakeTransport([deviceCode(), Exception('offline')]);
      final service = SimklService(
        storage: InMemorySecureStorage(),
        clientId: 'client',
        transport: transport.call,
      );
      addTearDown(service.dispose);
      await service.startDeviceAuth();

      await service.pollForTesting();

      expect(service.status, SimklAuthStatus.pending);
      expect(service.pending?.userCode, 'BDWP-HQPK');
    });

    test('an expired code stops the login', () async {
      final transport = _FakeTransport([
        deviceCode(),
        const SimklResponse(400, {'error': 'expired_token'}),
      ]);
      final service = SimklService(
        storage: InMemorySecureStorage(),
        clientId: 'client',
        transport: transport.call,
      );
      addTearDown(service.dispose);
      await service.startDeviceAuth();

      await service.pollForTesting();

      expect(service.status, SimklAuthStatus.disconnected);
      expect(service.pending, isNull);
    });

    test('approval stores the tokens and connects', () async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport([deviceCode(), tokens()]);
      final service = SimklService(
        storage: storage,
        clientId: 'client',
        transport: transport.call,
      );
      addTearDown(service.dispose);
      await service.startDeviceAuth();

      await service.pollForTesting();

      expect(service.isConnected, isTrue);
      expect(service.pending, isNull);
      expect(await storage.read(accessKey), 'simkl_at_new');
      expect(await storage.read(refreshKey), 'simkl_rt_new');
      expect(
        transport.requests.last.form?['grant_type'],
        'urn:ietf:params:oauth:grant-type:device_code',
      );
    });
  });

  group('session', () {
    test('restores a valid token without a request', () async {
      final transport = _FakeTransport([]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      expect(service.isConnected, isTrue);
      expect(transport.requests, isEmpty);
    });

    test('an offline refresh at boot stays signed in', () async {
      final storage = InMemorySecureStorage();
      await storage.write(accessKey, 'simkl_at_old');
      await storage.write(refreshKey, 'simkl_rt_old');
      await storage.write(expiryKey, '0');
      final service = SimklService(
        storage: storage,
        clientId: 'client',
        transport: _FakeTransport([Exception('offline')]).call,
      );
      addTearDown(service.dispose);

      await service.init();

      expect(service.isConnected, isTrue);
      expect(await storage.read(refreshKey), 'simkl_rt_old');
    });

    test('a rejected refresh signs out and clears tokens', () async {
      final storage = InMemorySecureStorage();
      await storage.write(accessKey, 'simkl_at_old');
      await storage.write(refreshKey, 'simkl_rt_old');
      await storage.write(expiryKey, '0');
      final service = SimklService(
        storage: storage,
        clientId: 'client',
        transport: _FakeTransport([
          const SimklResponse(400, {'error': 'invalid_grant'}),
        ]).call,
      );
      addTearDown(service.dispose);

      await service.init();

      expect(service.isConnected, isFalse);
      expect(await storage.read(accessKey), isNull);
      expect(await storage.read(refreshKey), isNull);
    });

    test('a refresh that returns no new refresh token keeps the old', () async {
      final storage = InMemorySecureStorage();
      await storage.write(accessKey, 'simkl_at_old');
      await storage.write(refreshKey, 'simkl_rt_old');
      await storage.write(expiryKey, '0');
      final service = SimklService(
        storage: storage,
        clientId: 'client',
        transport: _FakeTransport([
          const SimklResponse(200, {'access_token': 'simkl_at_new'}),
        ]).call,
      );
      addTearDown(service.dispose);

      await service.init();

      expect(service.isConnected, isTrue);
      expect(await storage.read(accessKey), 'simkl_at_new');
      expect(await storage.read(refreshKey), 'simkl_rt_old');
    });

    test('disconnect clears tokens and revokes the grant', () async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport([const SimklResponse(200, {})]);
      final service = await connected(transport, storage);
      addTearDown(service.dispose);

      await service.disconnect();

      expect(service.isConnected, isFalse);
      expect(await storage.read(accessKey), isNull);
      expect(transport.requests.single.path, '/oauth2/revoke');
      expect(transport.requests.single.form?['token'], 'simkl_rt_old');
    });
  });

  group('scrobble', () {
    test('does nothing while signed out', () async {
      final transport = _FakeTransport([]);
      final service = SimklService(
        storage: InMemorySecureStorage(),
        clientId: 'client',
        transport: transport.call,
      );
      addTearDown(service.dispose);

      await service.scrobble(action: 'start', title: 'Movie', progress: 0);

      expect(transport.requests, isEmpty);
    });

    test('opts out of the progress heartbeat', () {
      final service = SimklService(
        storage: InMemorySecureStorage(),
        clientId: 'client',
      );
      addTearDown(service.dispose);

      expect(service.wantsProgressHeartbeat, isFalse);
    });

    test('sends a movie with its title, year, and ids', () async {
      final transport = _FakeTransport([const SimklResponse(201, {})]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await service.scrobble(
        action: 'stop',
        title: 'Inception',
        tmdbId: 27205,
        imdbId: 'tt1375666',
        year: 2010,
        progress: 91.256,
      );

      final request = transport.requests.single;
      expect(request.path, '/scrobble/stop');
      expect(request.accessToken, 'simkl_at_old');
      expect(request.json, {
        'progress': 91.26,
        'movie': {
          'title': 'Inception',
          'year': 2010,
          'ids': {'tmdb': 27205, 'imdb': 'tt1375666'},
        },
      });
    });

    test('sends an episode under its show', () async {
      final transport = _FakeTransport([const SimklResponse(201, {})]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await service.scrobble(
        action: 'pause',
        title: 'Episode Title',
        seriesTitle: 'Stranger Things',
        season: 1,
        episode: 3,
        tmdbId: 66732,
        progress: 42,
      );

      expect(transport.requests.single.json, {
        'progress': 42.0,
        'show': {
          'title': 'Stranger Things',
          'ids': {'tmdb': 66732},
        },
        'episode': {'season': 1, 'number': 3},
      });
    });

    test('ignores an id that is not an IMDb id', () async {
      final transport = _FakeTransport([const SimklResponse(201, {})]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await service.scrobble(
        action: 'start',
        title: 'Movie',
        imdbId: 'aio-123',
        progress: 0,
      );

      expect(
        (transport.requests.single.json!['movie']! as Map).containsKey('ids'),
        isFalse,
      );
    });

    test('refreshes an expired token first', () async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport([
        tokens(),
        const SimklResponse(201, {}),
      ]);
      final service = await connected(transport, storage);
      addTearDown(service.dispose);
      await storage.write(expiryKey, '0');

      await service.scrobble(action: 'start', title: 'Movie', progress: 0);

      expect(transport.requests.map((request) => request.path), [
        '/oauth2/token',
        '/scrobble/start',
      ]);
      expect(transport.requests.last.accessToken, 'simkl_at_new');
    });

    test('a 401 refreshes and retries once', () async {
      final transport = _FakeTransport([
        const SimklResponse(401, {'error': 'invalid_token'}),
        tokens(),
        const SimklResponse(201, {}),
      ]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await service.scrobble(action: 'start', title: 'Movie', progress: 0);

      expect(transport.requests.map((request) => request.path), [
        '/scrobble/start',
        '/oauth2/token',
        '/scrobble/start',
      ]);
    });

    test('a stop that hits the write lock is retried', () async {
      final transport = _FakeTransport([
        const SimklResponse(400, {'error': 'RATE_LIMIT'}),
        const SimklResponse(201, {'action': 'scrobble'}),
      ]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await service.scrobble(action: 'stop', title: 'Movie', progress: 95);

      expect(transport.requests, hasLength(2));
      expect(transport.requests.last.path, '/scrobble/stop');
    });

    test('a start that hits the write lock is dropped', () async {
      final transport = _FakeTransport([
        const SimklResponse(400, {'error': 'RATE_LIMIT'}),
      ]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await service.scrobble(action: 'start', title: 'Movie', progress: 0);

      expect(transport.requests, hasLength(1));
    });

    test('events are sent one at a time, in order', () async {
      final transport = _FakeTransport([
        const SimklResponse(201, {}),
        const SimklResponse(201, {}),
      ]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await Future.wait([
        service.scrobble(action: 'start', title: 'Movie', progress: 0),
        service.scrobble(action: 'stop', title: 'Movie', progress: 90),
      ]);

      expect(transport.requests.map((request) => request.path), [
        '/scrobble/start',
        '/scrobble/stop',
      ]);
    });

    test('a failure never reaches the caller', () async {
      final transport = _FakeTransport([Exception('offline')]);
      final service = await connected(transport, InMemorySecureStorage());
      addTearDown(service.dispose);

      await expectLater(
        service.scrobble(action: 'start', title: 'Movie', progress: 0),
        completes,
      );
    });
  });
}

class _FakeTransport {
  _FakeTransport(this.responses);

  /// Each entry is a [SimklResponse] to return or an [Exception] to throw.
  final List<Object> responses;
  final requests = <SimklRequest>[];

  Future<SimklResponse> call(SimklRequest request) async {
    requests.add(request);
    final next = responses.removeAt(0);
    if (next is Exception) throw next;
    return next as SimklResponse;
  }
}
