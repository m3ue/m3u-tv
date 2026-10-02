import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

void main() {
  late HttpServer server;
  late List<(Uri, String)> requests;
  late UserCredentials credentials;

  setUp(() async {
    requests = <(Uri, String)>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        requests.add((request.uri, await utf8.decodeStream(request)));
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
    credentials = UserCredentials(
      server: 'http://127.0.0.1:${server.port}',
      username: 'user1',
      password: 'pass1',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('posts the stream id and client id to the stop endpoint', () async {
    await TvNotificationService().stopPlayerStream(
      credentials,
      type: 'catchup',
      streamId: 42,
      clientId: 'm3utv-abc',
    );

    final (uri, body) = requests.single;
    expect(uri.path, '/api/tv/user1/pass1/player-stream/stop');
    expect(jsonDecode(body), {
      'type': 'catchup',
      'stream_id': '42',
      'client_id': 'm3utv-abc',
    });
  });

  test('sends series sessions as an episode id', () async {
    await TvNotificationService().stopPlayerStream(
      credentials,
      type: 'series',
      streamId: 7,
      clientId: 'm3utv-abc',
    );

    final (_, body) = requests.single;
    expect(jsonDecode(body), {
      'type': 'series',
      'episode_id': '7',
      'client_id': 'm3utv-abc',
    });
  });
}
