import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/device_identity_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

void main() {
  late HttpServer server;
  late List<(Uri, String)> requests;

  setUp(() async {
    requests = <(Uri, String)>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        requests.add((request.uri, await utf8.decodeStream(request)));
        request.response
          ..headers.set('content-type', 'application/json')
          ..write(jsonEncode({'ok': true, 'id': 7}));
        await request.response.close();
      });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test("posts the report with this install's identity params", () async {
    final service = TvNotificationService(
      deviceIdentity: DeviceIdentityService(
        storage: InMemorySecureStorage(),
        appVersionResolver: () async => '1.1.4',
        metaResolver: () async =>
            const DeviceMeta(platform: 'androidtv', name: 'SHIELD'),
      ),
    );

    final id = await service.uploadLogs(
      UserCredentials(
        server: 'http://127.0.0.1:${server.port}',
        username: 'user1',
        password: 'pass1',
      ),
      'HEADER\n---\nline',
    );

    expect(id, 7);
    final (uri, body) = requests.single;
    expect(uri.path, '/api/tv/user1/pass1/logs');
    expect(uri.queryParameters['platform'], 'androidtv');
    expect(uri.queryParameters['device_name'], 'SHIELD');
    expect(uri.queryParameters['app_version'], '1.1.4');
    expect(uri.queryParameters['device_id'], isNotEmpty);
    expect(jsonDecode(body), {'log': 'HEADER\n---\nline'});
  });

  test('refuses to upload without a device identity', () async {
    final service = TvNotificationService();

    expect(
      () => service.uploadLogs(
        UserCredentials(
          server: 'http://127.0.0.1:${server.port}',
          username: 'user1',
          password: 'pass1',
        ),
        'x',
      ),
      throwsStateError,
    );
  });
}
