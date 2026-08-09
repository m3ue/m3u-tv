import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';

void main() {
  group('DevicePairingService', () {
    test('start requests a code and enters pending status', () async {
      final transport = _FakeTransport([
        _codeResponse(interval: 3600),
      ]);
      final service = DevicePairingService(transport: transport.call);
      addTearDown(service.dispose);

      await service.start('192.168.1.10:8080');

      expect(service.status, DevicePairingStatus.pending);
      expect(service.pending?.userCode, 'ABCD-1234');
      expect(service.pending?.verificationUri, contains('code=ABCD-1234'));
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.server, 'http://192.168.1.10:8080');
      expect(transport.requests.single.path, '/api/device/code');
    });

    test(
      'approved poll response yields credentials and stops polling',
      () async {
        final transport = _FakeTransport([
          _codeResponse(interval: 3600),
          _approvedResponse(username: 'tv-user', password: 'tv-pass'),
        ]);
        final service = DevicePairingService(transport: transport.call);
        addTearDown(service.dispose);

        await service.start('http://example.com');
        await service.pollForTesting('http://example.com');

        expect(service.status, DevicePairingStatus.approved);
        expect(service.result?.server, 'http://example.com');
        expect(service.result?.username, 'tv-user');
        expect(service.result?.password, 'tv-pass');
      },
    );

    test('pending poll response keeps polling state', () async {
      final transport = _FakeTransport([
        _codeResponse(interval: 3600),
        _statusResponse('pending'),
      ]);
      final service = DevicePairingService(transport: transport.call);
      addTearDown(service.dispose);

      await service.start('http://example.com');
      await service.pollForTesting('http://example.com');

      expect(service.status, DevicePairingStatus.pending);
    });

    test('slow_down response increases the polling interval', () async {
      final transport = _FakeTransport([
        _codeResponse(interval: 10),
        _statusResponse('slow_down', extra: {'interval': 15}),
      ]);
      final service = DevicePairingService(transport: transport.call);
      addTearDown(service.dispose);

      await service.start('http://example.com');
      await service.pollForTesting('http://example.com');

      expect(service.status, DevicePairingStatus.pending);
      expect(service.pollIntervalForTesting, const Duration(seconds: 15));
    });

    test('expired poll response moves to error status', () async {
      final transport = _FakeTransport([
        _codeResponse(interval: 10),
        _statusResponse('expired'),
      ]);
      final service = DevicePairingService(transport: transport.call);
      addTearDown(service.dispose);

      await service.start('http://example.com');
      await service.pollForTesting('http://example.com');

      expect(service.status, DevicePairingStatus.error);
    });

    test('denied poll response moves to error status', () async {
      final transport = _FakeTransport([
        _codeResponse(interval: 10),
        _statusResponse('denied'),
      ]);
      final service = DevicePairingService(transport: transport.call);
      addTearDown(service.dispose);

      await service.start('http://example.com');
      await service.pollForTesting('http://example.com');

      expect(service.status, DevicePairingStatus.error);
    });

    test('cancel resets to idle and stops further polling', () async {
      final transport = _FakeTransport([
        _codeResponse(interval: 3600),
      ]);
      final service = DevicePairingService(transport: transport.call);
      addTearDown(service.dispose);

      await service.start('http://example.com');
      service.cancel();

      expect(service.status, DevicePairingStatus.idle);
      expect(service.pending, isNull);
    });

    test('a code request failure moves to error status', () async {
      final transport = _FailingTransport();
      final service = DevicePairingService(transport: transport.call);
      addTearDown(service.dispose);

      await service.start('http://example.com');

      expect(service.status, DevicePairingStatus.error);
    });
  });
}

DevicePairingResponse _codeResponse({
  required int interval,
  int expiresIn = 600,
}) {
  return DevicePairingResponse(200, <String, Object?>{
    'device_code': 'DEVICE-CODE',
    'user_code': 'ABCD-1234',
    'verification_uri': 'http://example.com/device-pairing?code=ABCD-1234',
    'interval': interval,
    'expires_in': expiresIn,
  });
}

DevicePairingResponse _approvedResponse({
  required String username,
  required String password,
}) {
  return DevicePairingResponse(200, <String, Object?>{
    'status': 'approved',
    'username': username,
    'password': password,
  });
}

DevicePairingResponse _statusResponse(
  String status, {
  Map<String, Object?> extra = const {},
}) {
  return DevicePairingResponse(200, <String, Object?>{
    'status': status,
    ...extra,
  });
}

class _FakeTransport {
  _FakeTransport(this._responses);

  final List<DevicePairingResponse> _responses;
  final requests = <DevicePairingRequest>[];

  Future<DevicePairingResponse> call(DevicePairingRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) {
      return const DevicePairingResponse(500, <String, Object?>{});
    }
    return _responses.removeAt(0);
  }
}

class _FailingTransport {
  Future<DevicePairingResponse> call(DevicePairingRequest request) {
    throw StateError('network error');
  }
}
