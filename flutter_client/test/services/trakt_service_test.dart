import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';

void main() {
  const clientId = 'public-client-id';
  const accessKey = 'trakt_access_token';
  const refreshKey = 'trakt_refresh_token';
  const expiryKey = 'trakt_token_expiry';
  const rfcVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  const rfcChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

  group('TraktService device authentication', () {
    test('device code request sends public client PKCE fields', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
      ]);
      final service = _service(
        transport,
        codeVerifierFactory: () => rfcVerifier,
      );
      addTearDown(service.dispose);

      await service.startDeviceAuth();

      expect(service.status, TraktAuthStatus.pending);
      expect(service.pending?.userCode, 'USER-CODE');
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.path, '/oauth/device/code');
      expect(transport.requests.single.body, const <String, Object>{
        'client_id': clientId,
        'code_challenge': rfcChallenge,
        'code_challenge_method': 'S256',
      });
      expect(transport.requests.single.body, isNot(contains('client_secret')));
    });

    test('device token polling sends no secret and persists tokens', () async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        _tokenResponse(
          accessToken: 'access-token-sentinel',
          refreshToken: 'refresh-token-sentinel',
        ),
      ]);
      final service = _service(
        transport,
        storage: storage,
        codeVerifierFactory: () => rfcVerifier,
      );
      addTearDown(service.dispose);

      await service.startDeviceAuth();
      await service.pollForTesting();

      expect(service.status, TraktAuthStatus.connected);
      expect(service.pending, isNull);
      final tokenRequest = transport.requests.singleWhere(
        (request) => request.path == '/oauth/device/token',
      );
      expect(tokenRequest.body, const <String, Object>{
        'code': 'DEVICE-CODE',
        'client_id': clientId,
        'code_verifier': rfcVerifier,
      });
      expect(tokenRequest.body, isNot(contains('client_secret')));
      expect(await storage.read(accessKey), 'access-token-sentinel');
      expect(await storage.read(refreshKey), 'refresh-token-sentinel');
      expect(await storage.read(expiryKey), isNotNull);
    });

    test('creates a fresh RFC 7636 verifier for every auth attempt', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600, deviceCode: 'DEVICE-ONE'),
        const TraktResponse(400, <String, Object?>{
          'error': 'authorization_pending',
        }),
        _deviceCodeResponse(interval: 3600, deviceCode: 'DEVICE-TWO'),
        const TraktResponse(400, <String, Object?>{
          'error': 'authorization_pending',
        }),
      ]);
      final service = _service(transport);
      addTearDown(service.dispose);

      await service.startDeviceAuth();
      await service.pollForTesting();
      await service.startDeviceAuth();
      await service.pollForTesting();

      final tokenRequests = transport.requests
          .where((request) => request.path == '/oauth/device/token')
          .toList();
      expect(tokenRequests, hasLength(2));
      expect(
        tokenRequests[0].body['code_verifier'],
        isNot(tokenRequests[1].body['code_verifier']),
      );
      for (final request in tokenRequests) {
        final verifier = request.body['code_verifier']! as String;
        expect(verifier.length, inInclusiveRange(43, 128));
        expect(verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
      }
    });

    test(
      'an old device response cannot replace a newer PKCE attempt',
      () async {
        const firstVerifier =
            'first-verifier-abcdefghijklmnopqrstuvwxyz0123456789-._~';
        const secondVerifier =
            'second-verifier-abcdefghijklmnopqrstuvwxyz0123456789-._~';
        final verifiers = <String>[firstVerifier, secondVerifier];
        final firstResponse = Completer<TraktResponse>();
        final transport = _ControlledTraktTransport(firstResponse.future);
        final service = TraktService(
          storage: InMemorySecureStorage(),
          clientId: clientId,
          transport: transport.call,
          codeVerifierFactory: () => verifiers.removeAt(0),
        );
        addTearDown(service.dispose);

        final oldAttempt = service.startDeviceAuth();
        await service.startDeviceAuth();
        firstResponse.complete(
          _deviceCodeResponse(interval: 3600, deviceCode: 'OLD-DEVICE'),
        );
        await oldAttempt;
        await service.pollForTesting();

        expect(service.pending?.deviceCode, 'NEW-DEVICE');
        final tokenRequest = transport.requests.singleWhere(
          (request) => request.path == '/oauth/device/token',
        );
        expect(tokenRequest.body['code'], 'NEW-DEVICE');
        expect(tokenRequest.body['code_verifier'], secondVerifier);
      },
    );

    test('cancel and dispose prevent reuse of a pending verifier', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        _deviceCodeResponse(interval: 3600),
      ]);
      final service = _service(
        transport,
        codeVerifierFactory: () => rfcVerifier,
      );

      await service.startDeviceAuth();
      service.cancelAuth();
      await service.pollForTesting();
      await service.startDeviceAuth();
      service.dispose();
      await service.pollForTesting();

      expect(
        transport.requests.where(
          (request) => request.path == '/oauth/device/token',
        ),
        isEmpty,
      );
    });

    test('pending device token response keeps polling state', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        const TraktResponse(400, <String, Object?>{
          'error': 'authorization_pending',
          'device_code': 'DEVICE-CODE',
        }),
      ]);
      final service = _service(transport);
      addTearDown(service.dispose);

      await service.startDeviceAuth();
      await service.pollForTesting();

      expect(service.status, TraktAuthStatus.pending);
      expect(service.pending?.deviceCode, 'DEVICE-CODE');
    });

    test('slow down response increases the polling interval', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 10),
        const TraktResponse(400, <String, Object?>{
          'error': 'slow_down',
        }),
      ]);
      final service = _service(transport);
      addTearDown(service.dispose);

      await service.startDeviceAuth();
      await service.pollForTesting();

      expect(service.status, TraktAuthStatus.pending);
      expect(service.pollIntervalForTesting, const Duration(seconds: 15));
    });

    test('device authorization stops locally when its code expires', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 10, expiresIn: 0),
      ]);
      final service = _service(transport);
      addTearDown(service.dispose);

      await service.startDeviceAuth();

      expect(service.status, TraktAuthStatus.disconnected);
      expect(service.pending, isNull);
      expect(
        transport.requests.where(
          (request) => request.path == '/oauth/device/token',
        ),
        isEmpty,
      );
    });

    test('expired device token response cancels pending auth', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        const TraktResponse(400, <String, Object?>{
          'error': 'expired_token',
          'device_code': 'DEVICE-CODE',
        }),
      ]);
      final service = _service(transport);
      addTearDown(service.dispose);

      await service.startDeviceAuth();
      await service.pollForTesting();

      expect(service.status, TraktAuthStatus.disconnected);
      expect(service.pending, isNull);
    });

    test('denied device token response cancels pending auth', () async {
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        const TraktResponse(400, <String, Object?>{
          'error': 'access_denied',
        }),
      ]);
      final service = _service(transport);
      addTearDown(service.dispose);

      await service.startDeviceAuth();
      await service.pollForTesting();

      expect(service.status, TraktAuthStatus.disconnected);
      expect(service.pending, isNull);
    });

    test(
      'cancel auth clears pending state without deleting stored tokens',
      () async {
        final storage = InMemorySecureStorage();
        await storage.write(accessKey, 'stored-access-token');
        await storage.write(refreshKey, 'stored-refresh-token');
        await storage.write(expiryKey, '${_futureEpoch()}');
        final transport = _FakeTraktTransport([
          _deviceCodeResponse(interval: 3600),
        ]);
        final service = _service(transport, storage: storage);
        addTearDown(service.dispose);

        await service.startDeviceAuth();
        service.cancelAuth();

        expect(service.status, TraktAuthStatus.disconnected);
        expect(service.pending, isNull);
        expect(await storage.read(accessKey), 'stored-access-token');
        expect(await storage.read(refreshKey), 'stored-refresh-token');
        expect(await storage.read(expiryKey), isNotNull);
      },
    );
  });

  group('TraktService session lifecycle', () {
    test('init stops cleanly when disposed during storage read', () async {
      final storage = _BlockingAccessReadSecureStorage();
      final service = TraktService(
        storage: storage,
        clientId: clientId,
      );

      final initializing = service.init();
      await storage.accessReadStarted.future;
      service.dispose();
      storage.releaseAccess('stored-access-token');

      await expectLater(initializing, completes);
    });

    test('init restores a valid stored session', () async {
      final storage = InMemorySecureStorage();
      await storage.write(accessKey, 'stored-access-token');
      await storage.write(refreshKey, 'stored-refresh-token');
      await storage.write(expiryKey, '${_futureEpoch()}');
      final service = _service(_FakeTraktTransport([]), storage: storage);
      addTearDown(service.dispose);

      await service.init();

      expect(service.status, TraktAuthStatus.connected);
      expect(await storage.read(accessKey), 'stored-access-token');
      expect(await storage.read(refreshKey), 'stored-refresh-token');
    });

    test(
      'expired session refresh sends no secret and replaces tokens',
      () async {
        final storage = InMemorySecureStorage();
        await storage.write(accessKey, 'old-access-token');
        await storage.write(refreshKey, 'old-refresh-token');
        await storage.write(expiryKey, '${_pastEpoch()}');
        final transport = _FakeTraktTransport([
          _tokenResponse(
            accessToken: 'new-access-token',
            refreshToken: 'new-refresh-token',
          ),
        ]);
        final service = _service(transport, storage: storage);
        addTearDown(service.dispose);

        await service.init();

        expect(service.status, TraktAuthStatus.connected);
        expect(transport.requests.single.path, '/oauth/token');
        expect(transport.requests.single.body, const <String, Object>{
          'refresh_token': 'old-refresh-token',
          'client_id': clientId,
          'grant_type': 'refresh_token',
        });
        expect(
          transport.requests.single.body,
          isNot(contains('client_secret')),
        );
        expect(
          transport.requests.single.body,
          isNot(contains('code_verifier')),
        );
        expect(await storage.read(accessKey), 'new-access-token');
        expect(await storage.read(refreshKey), 'new-refresh-token');
      },
    );

    test('failed refresh clears stored tokens', () async {
      final storage = InMemorySecureStorage();
      await storage.write(accessKey, 'old-access-token');
      await storage.write(refreshKey, 'old-refresh-token');
      await storage.write(expiryKey, '${_pastEpoch()}');
      final transport = _FakeTraktTransport([
        const TraktResponse(400, <String, Object?>{
          'error': 'invalid_grant',
          'refresh_token': 'old-refresh-token',
        }),
      ]);
      final service = _service(transport, storage: storage);
      addTearDown(service.dispose);

      await service.init();

      expect(service.status, TraktAuthStatus.disconnected);
      expect(await storage.read(accessKey), isNull);
      expect(await storage.read(refreshKey), isNull);
      expect(await storage.read(expiryKey), isNull);
    });

    test('disconnect clears connected state and stored tokens', () async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        _tokenResponse(
          accessToken: 'access-token-sentinel',
          refreshToken: 'refresh-token-sentinel',
        ),
      ]);
      final service = _service(transport, storage: storage);
      addTearDown(service.dispose);
      await service.startDeviceAuth();
      await service.pollForTesting();

      await service.disconnect();

      expect(service.status, TraktAuthStatus.disconnected);
      expect(service.pending, isNull);
      expect(await storage.read(accessKey), isNull);
      expect(await storage.read(refreshKey), isNull);
      expect(await storage.read(expiryKey), isNull);
    });

    test(
      'cancel keeps prior tokens when a save is already in progress',
      () async {
        final storage = _BlockingWriteSecureStorage({
          accessKey: 'stored-access-token',
          refreshKey: 'stored-refresh-token',
          expiryKey: '${_futureEpoch()}',
        });
        final transport = _FakeTraktTransport([
          _deviceCodeResponse(interval: 3600),
          _tokenResponse(
            accessToken: 'stale-access-token',
            refreshToken: 'stale-refresh-token',
          ),
        ]);
        final service = TraktService(
          storage: storage,
          clientId: clientId,
          transport: transport.call,
          codeVerifierFactory: () => rfcVerifier,
        );
        addTearDown(service.dispose);
        await service.startDeviceAuth();

        final poll = service.pollForTesting();
        await storage.writeStarted.future;
        service.cancelAuth();
        storage.releaseWrite();
        await poll;

        expect(service.status, TraktAuthStatus.disconnected);
        expect(await storage.read(accessKey), 'stored-access-token');
        expect(await storage.read(refreshKey), 'stored-refresh-token');
        expect(await storage.read(expiryKey), isNotNull);
      },
    );

    test('disconnect wins against a token save already in progress', () async {
      final storage = _BlockingWriteSecureStorage();
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        _tokenResponse(
          accessToken: 'stale-access-token',
          refreshToken: 'stale-refresh-token',
        ),
      ]);
      final service = TraktService(
        storage: storage,
        clientId: clientId,
        transport: transport.call,
        codeVerifierFactory: () => rfcVerifier,
      );
      addTearDown(service.dispose);
      await service.startDeviceAuth();

      final poll = service.pollForTesting();
      await storage.writeStarted.future;
      final disconnect = service.disconnect();
      storage.releaseWrite();
      await Future.wait([poll, disconnect]);

      expect(service.status, TraktAuthStatus.disconnected);
      expect(await storage.read(accessKey), isNull);
      expect(await storage.read(refreshKey), isNull);
      expect(await storage.read(expiryKey), isNull);
    });

    test('failed token save restores the previous credential set', () async {
      final storage = _FailOnceSecureStorage(
        {
          accessKey: 'stored-access-token',
          refreshKey: 'stored-refresh-token',
          expiryKey: '${_futureEpoch()}',
        },
        failKey: refreshKey,
      );
      final transport = _FakeTraktTransport([
        _deviceCodeResponse(interval: 3600),
        _tokenResponse(
          accessToken: 'replacement-access-token',
          refreshToken: 'replacement-refresh-token',
        ),
      ]);
      final service = TraktService(
        storage: storage,
        clientId: clientId,
        transport: transport.call,
        codeVerifierFactory: () => rfcVerifier,
      );
      addTearDown(service.dispose);
      await service.startDeviceAuth();
      await service.pollForTesting();

      expect(service.status, TraktAuthStatus.disconnected);
      expect(await storage.read(accessKey), 'stored-access-token');
      expect(await storage.read(refreshKey), 'stored-refresh-token');
      expect(await storage.read(expiryKey), isNotNull);

      final restored = _service(_FakeTraktTransport([]), storage: storage);
      addTearDown(restored.dispose);
      await restored.init();
      expect(restored.status, TraktAuthStatus.connected);
    });
  });

  group('TraktService scrobble redaction', () {
    test(
      'scrobble success sends media payload but logs no sensitive values',
      () async {
        final logs = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
        addTearDown(() => debugPrint = previousDebugPrint);
        final storage = InMemorySecureStorage();
        await storage.write(accessKey, 'access-token-sentinel');
        await storage.write(refreshKey, 'refresh-token-sentinel');
        await storage.write(expiryKey, '${_futureEpoch()}');
        final transport = _FakeTraktTransport([
          const TraktResponse(201, <String, Object?>{}),
        ]);
        final service = _service(transport, storage: storage);
        addTearDown(service.dispose);
        await service.init();

        await service.scrobble(
          action: 'start',
          title: 'Sensitive Movie Title',
          tmdbId: 123456,
          imdbId: 'tt7654321',
          progress: 42.5,
        );

        expect(transport.requests.single.path, '/scrobble/start');
        expect(transport.requests.single.accessToken, 'access-token-sentinel');
        expect(
          transport.requests.single.body.toString(),
          contains('Sensitive Movie Title'),
        );
        _expectLogsRedacted(logs.join('\n'));
      },
    );

    test('scrobble failure logs no error body or media values', () async {
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = previousDebugPrint);
      final storage = InMemorySecureStorage();
      await storage.write(accessKey, 'access-token-sentinel');
      await storage.write(refreshKey, 'refresh-token-sentinel');
      await storage.write(expiryKey, '${_futureEpoch()}');
      final transport = _FakeTraktTransport([
        const TraktResponse(500, <String, Object?>{
          'error_description': 'Sensitive Movie Title response body leak',
          'access_token': 'access-token-sentinel',
        }),
      ]);
      final service = _service(transport, storage: storage);
      addTearDown(service.dispose);
      await service.init();

      await service.scrobble(
        action: 'pause',
        title: 'Episode Title Secret',
        seriesTitle: 'Sensitive Show Title',
        season: 2,
        episode: 7,
        tmdbId: 987654,
        progress: 88.25,
      );

      _expectLogsRedacted(logs.join('\n'));
    });
  });
}

TraktService _service(
  _FakeTraktTransport transport, {
  SecureStorage? storage,
  String Function()? codeVerifierFactory,
}) {
  return TraktService(
    storage: storage ?? InMemorySecureStorage(),
    clientId: 'public-client-id',
    transport: transport.call,
    codeVerifierFactory: codeVerifierFactory,
  );
}

TraktResponse _deviceCodeResponse({
  required int interval,
  String deviceCode = 'DEVICE-CODE',
  int expiresIn = 600,
}) {
  return TraktResponse(200, <String, Object?>{
    'user_code': 'USER-CODE',
    'verification_url': 'https://trakt.tv/activate',
    'device_code': deviceCode,
    'interval': interval,
    'expires_in': expiresIn,
  });
}

TraktResponse _tokenResponse({
  required String accessToken,
  required String refreshToken,
}) {
  return TraktResponse(200, <String, Object?>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_in': 3600,
  });
}

int _futureEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;

int _pastEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;

void _expectLogsRedacted(String logs) {
  for (final sensitiveValue in <String>[
    'access-token-sentinel',
    'refresh-token-sentinel',
    'Sensitive Movie Title',
    'Episode Title Secret',
    'Sensitive Show Title',
    'tt7654321',
    '123456',
    '987654',
    '42.5',
    '88.25',
    'DEVICE-CODE',
    'response body leak',
  ]) {
    expect(logs, isNot(contains(sensitiveValue)), reason: sensitiveValue);
  }
}

class _FakeTraktTransport {
  _FakeTraktTransport(this._responses);

  final List<TraktResponse> _responses;
  final requests = <TraktRequest>[];

  Future<TraktResponse> call(TraktRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) {
      return const TraktResponse(500, <String, Object?>{});
    }
    return _responses.removeAt(0);
  }
}

class _BlockingAccessReadSecureStorage implements SecureStorage {
  final accessReadStarted = Completer<void>();
  final _access = Completer<String?>();

  void releaseAccess(String? value) => _access.complete(value);

  @override
  Future<String?> read(String key) {
    if (key == 'trakt_access_token') {
      accessReadStarted.complete();
      return _access.future;
    }
    if (key == 'trakt_token_expiry') {
      return Future<String?>.value('${_futureEpoch()}');
    }
    return Future<String?>.value();
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

class _BlockingWriteSecureStorage implements SecureStorage {
  _BlockingWriteSecureStorage([Map<String, String>? initialValues])
    : _values = {...?initialValues};

  final Map<String, String> _values;
  final writeStarted = Completer<void>();
  final _writeReleased = Completer<void>();
  var _blockFirstWrite = true;

  void releaseWrite() => _writeReleased.complete();

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (_blockFirstWrite) {
      _blockFirstWrite = false;
      writeStarted.complete();
      await _writeReleased.future;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FailOnceSecureStorage implements SecureStorage {
  _FailOnceSecureStorage(
    Map<String, String> initialValues, {
    required this.failKey,
  }) : _values = {...initialValues};

  final Map<String, String> _values;
  final String failKey;
  var _hasFailed = false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == failKey && !_hasFailed) {
      _hasFailed = true;
      throw StateError('injected write failure');
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _ControlledTraktTransport {
  _ControlledTraktTransport(this.firstDeviceResponse);

  final Future<TraktResponse> firstDeviceResponse;
  final requests = <TraktRequest>[];
  var _deviceRequestCount = 0;

  Future<TraktResponse> call(TraktRequest request) async {
    requests.add(request);
    if (request.path == '/oauth/device/code') {
      _deviceRequestCount += 1;
      if (_deviceRequestCount == 1) return firstDeviceResponse;
      return _deviceCodeResponse(interval: 3600, deviceCode: 'NEW-DEVICE');
    }
    if (request.path == '/oauth/device/token') {
      return const TraktResponse(400, <String, Object?>{
        'error': 'authorization_pending',
      });
    }
    return const TraktResponse(500, <String, Object?>{});
  }
}
