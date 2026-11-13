import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/mdblist_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';

void main() {
  String futureExpiry() =>
      '${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400}';

  MdblistResponse deviceCode() => const MdblistResponse(200, {
    'device_code': 'device-secret',
    'user_code': 'WDJB-MJHT',
    'verification_uri': 'https://mdblist.com/oauth/device/',
    'verification_uri_complete':
        'https://mdblist.com/oauth/device/?user_code=WDJB-MJHT',
    'expires_in': 300,
    'interval': 3600,
  });

  Future<MdblistService> connected(
    _FakeTransport transport,
    InMemorySecureStorage storage,
  ) async {
    await storage.write('mdblist_access_token', 'at_old');
    await storage.write('mdblist_refresh_token', 'rt_old');
    await storage.write('mdblist_token_expiry', futureExpiry());
    final service = MdblistService(
      storage: storage,
      clientId: 'client',
      transport: transport.call,
    );
    addTearDown(service.dispose);
    await service.init();
    return service;
  }

  test('is unavailable without a client id', () async {
    final transport = _FakeTransport([]);
    final service = MdblistService(
      storage: InMemorySecureStorage(),
      // ignore: avoid_redundant_argument_values
      clientId: '',
      transport: transport.call,
    );
    addTearDown(service.dispose);

    expect(service.isConfigured, isFalse);
    await service.startDeviceAuth();

    expect(transport.requests, isEmpty);
    expect(service.status, MdblistAuthStatus.disconnected);
  });

  test('signs in with the device flow and saves the tokens', () async {
    final storage = InMemorySecureStorage();
    final transport = _FakeTransport([
      deviceCode(),
      const MdblistResponse(400, {'error': 'authorization_pending'}),
      const MdblistResponse(200, {
        'access_token': 'at_new',
        'refresh_token': 'rt_new',
        'expires_in': 2592000,
      }),
    ]);
    final service = MdblistService(
      storage: storage,
      clientId: 'client',
      transport: transport.call,
    );
    addTearDown(service.dispose);

    await service.startDeviceAuth();
    expect(service.pending?.userCode, 'WDJB-MJHT');
    expect(
      service.pending?.completeUrl,
      'https://mdblist.com/oauth/device/?user_code=WDJB-MJHT',
    );
    final start = transport.requests.single;
    expect(start.path, '/oauth/device-authorization/');
    expect(start.form, {'client_id': 'client', 'scope': 'write'});

    await service.pollForTesting();
    expect(service.status, MdblistAuthStatus.pending);

    await service.pollForTesting();
    expect(service.status, MdblistAuthStatus.connected);
    final token = transport.requests.last;
    expect(token.path, '/oauth/token/');
    expect(
      token.form?['grant_type'],
      'urn:ietf:params:oauth:grant-type:device_code',
    );
    expect(token.form?['device_code'], 'device-secret');
    expect(await storage.read('mdblist_access_token'), 'at_new');
    expect(await storage.read('mdblist_refresh_token'), 'rt_new');
  });

  test('scrobbles a movie in the Trakt shape', () async {
    final transport = _FakeTransport([const MdblistResponse(201, {})]);
    final service = await connected(transport, InMemorySecureStorage());

    await service.scrobble(
      action: 'pause',
      title: 'The Matrix',
      tmdbId: 603,
      year: 1999,
      progress: 25.456,
    );

    final request = transport.requests.single;
    expect(request.path, '/scrobble/pause');
    expect(request.accessToken, 'at_old');
    expect(request.json, {
      'progress': 25.46,
      'movie': {
        'title': 'The Matrix',
        'year': 1999,
        'ids': {'tmdb': 603},
      },
    });
  });

  test('nests an episode inside the show', () {
    expect(
      MdblistService.scrobbleBody(
        title: "Cat's in the Bag...",
        seriesTitle: 'Breaking Bad',
        season: 1,
        episode: 2,
        tmdbId: 1396,
        progress: 95,
      ),
      {
        'progress': 95.0,
        'show': {
          'title': 'Breaking Bad',
          'ids': {'tmdb': 1396},
          'season': {
            'number': 1,
            'episode': {'number': 2},
          },
        },
      },
    );
  });

  test('refreshes and retries once on a 401', () async {
    final storage = InMemorySecureStorage();
    final transport = _FakeTransport([
      const MdblistResponse(401, {}),
      const MdblistResponse(200, {
        'access_token': 'at_new',
        'refresh_token': 'rt_new',
      }),
      const MdblistResponse(201, {}),
    ]);
    final service = await connected(transport, storage);

    await service.scrobble(
      action: 'stop',
      title: 'The Matrix',
      tmdbId: 603,
      progress: 92,
    );

    expect(transport.requests.map((request) => request.path), [
      '/scrobble/stop',
      '/oauth/token/',
      '/scrobble/stop',
    ]);
    expect(transport.requests.last.accessToken, 'at_new');
  });

  test('a rejected refresh token signs out', () async {
    final storage = InMemorySecureStorage();
    final transport = _FakeTransport([
      const MdblistResponse(401, {}),
      const MdblistResponse(400, {'error': 'invalid_grant'}),
    ]);
    final service = await connected(transport, storage);

    await service.scrobble(
      action: 'stop',
      title: 'The Matrix',
      tmdbId: 603,
      progress: 92,
    );

    expect(service.status, MdblistAuthStatus.disconnected);
    expect(await storage.read('mdblist_access_token'), isNull);
  });

  test('disconnect revokes the access token', () async {
    final storage = InMemorySecureStorage();
    final transport = _FakeTransport([const MdblistResponse(200, {})]);
    final service = await connected(transport, storage);

    await service.disconnect();

    final request = transport.requests.single;
    expect(request.path, '/oauth/revoke_token/');
    expect(request.form, {'client_id': 'client', 'token': 'at_old'});
    expect(await storage.read('mdblist_refresh_token'), isNull);
  });
}

class _FakeTransport {
  _FakeTransport(this.responses);

  /// Each entry is a [MdblistResponse] to return or an [Exception] to throw.
  final List<Object> responses;
  final requests = <MdblistRequest>[];

  Future<MdblistResponse> call(MdblistRequest request) async {
    requests.add(request);
    final next = responses.removeAt(0);
    if (next is Exception) throw next;
    return next as MdblistResponse;
  }
}
