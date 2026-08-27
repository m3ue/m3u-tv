import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

void main() {
  group('TvNotificationService base URL handling', () {
    late HttpServer server;
    late List<Uri> requested;

    setUp(() async {
      requested = <Uri>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((request) async {
          requested.add(request.uri);
          final body = jsonEncode(<String, Object?>{
            'notifiable_id': 1,
            'notifiable_type': 'playlist',
            'notifications': <Object?>[],
            'reverb': <String, Object?>{},
          });
          request.response
            ..headers.set('content-type', 'application/json')
            ..write(body);
          await request.response.close();
        });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<void> fetchWith(String rawServer) async {
      final service = TvNotificationService();
      await service.fetchUnread(
        UserCredentials(
          server: rawServer,
          username: 'user1',
          password: 'pass1',
        ),
      );
    }

    test(
      'reaches the endpoint when the server URL includes a scheme',
      () async {
        await fetchWith('http://127.0.0.1:${server.port}');

        expect(requested, hasLength(1));
        expect(requested.single.path, '/api/tv/user1/pass1/notifications');
      },
    );

    test('reaches the endpoint when the server URL omits the scheme', () async {
      // Regression: a bare host (scheme loosened on the connect form) used to
      // parse as a path with no host, so the notifications call - and the
      // device-registry upsert it carries - silently failed.
      await fetchWith('127.0.0.1:${server.port}');

      expect(requested, hasLength(1));
      expect(requested.single.path, '/api/tv/user1/pass1/notifications');
    });
  });
}
