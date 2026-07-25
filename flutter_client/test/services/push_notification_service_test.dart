import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/push_notification_service.dart';

void main() {
  group('PushNotificationService', () {
    test(
      'registers foreground, opened-app, and cold-start handlers once',
      () async {
        final messaging = _FakePushMessagingClient(
          initialMessage: const PushMessage(
            data: <String, String>{'notification_id': _firstId},
          ),
        );
        final service = PushNotificationService(messagingClient: messaging);
        final foreground = <PushMessage>[];
        final opened = <PushMessage>[];

        final first = service.init(
          onForegroundMessage: foreground.add,
          onMessageOpenedApp: opened.add,
        );
        final second = service.init(
          onForegroundMessage: foreground.add,
          onMessageOpenedApp: opened.add,
        );
        expect(await first, 'device-token');
        expect(await second, 'device-token');

        messaging
          ..emitForeground(
            const PushMessage(
              data: <String, String>{'notification_id': _secondId},
            ),
          )
          ..emitOpened(
            const PushMessage(
              data: <String, String>{'notification_id': _thirdId},
            ),
          );
        await Future<void>.delayed(Duration.zero);

        expect(messaging.initializeCalls, 1);
        expect(messaging.foregroundListenerCount, 1);
        expect(messaging.openedListenerCount, 1);
        expect(messaging.initialMessageCalls, 1);
        expect(foreground.map((message) => message.notificationId), [
          _secondId,
        ]);
        expect(opened.map((message) => message.notificationId), [
          _firstId,
          _thirdId,
        ]);
      },
    );

    test('uses requester-scoped subscribe and unsubscribe contracts', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <(String, String, Map<String, Object?>)>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        requests.add((
          request.method,
          request.uri.path,
          (body as Map).cast<String, Object?>(),
        ));
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json',
        );
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      final service = PushNotificationService();
      final credentials = UserCredentials(
        server: 'http://${server.address.host}:${server.port}/player_api.php',
        username: 'fixture user',
        password: 'fixture value',
      );

      await service.registerToken(
        credentials,
        token: 'old-token',
        platform: 'android',
      );
      await service.unregisterToken(credentials, token: 'old-token');

      expect(requests.map((request) => request.$1), <String>['POST', 'DELETE']);
      expect(requests.map((request) => request.$2), <String>[
        '/api/tv/fixture%20user/fixture%20value/push/subscribe',
        '/api/tv/fixture%20user/fixture%20value/push/unsubscribe',
      ]);
      expect(requests.first.$3, <String, Object?>{
        'token': 'old-token',
        'platform': 'android',
      });
      expect(requests.last.$3, <String, Object?>{'token': 'old-token'});
    });
  });
}

const _firstId = '11111111-1111-4111-8111-111111111111';
const _secondId = '22222222-2222-4222-8222-222222222222';
const _thirdId = '33333333-3333-4333-8333-333333333333';

class _FakePushMessagingClient implements PushMessagingClient {
  _FakePushMessagingClient({this.initialMessage});

  final PushMessage? initialMessage;
  final StreamController<PushMessage> _foreground =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> _opened =
      StreamController<PushMessage>.broadcast();
  final StreamController<String> _tokens = StreamController<String>.broadcast();

  int initializeCalls = 0;
  int foregroundListenerCount = 0;
  int openedListenerCount = 0;
  int initialMessageCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> getToken() async => 'device-token';

  @override
  Stream<PushMessage> get onForegroundMessage {
    foregroundListenerCount += 1;
    return _foreground.stream;
  }

  @override
  Stream<PushMessage> get onMessageOpenedApp {
    openedListenerCount += 1;
    return _opened.stream;
  }

  @override
  Stream<String> get onTokenRefresh => _tokens.stream;

  @override
  Future<PushMessage?> getInitialMessage() async {
    initialMessageCalls += 1;
    return initialMessage;
  }

  void emitForeground(PushMessage message) => _foreground.add(message);

  void emitOpened(PushMessage message) => _opened.add(message);
}
