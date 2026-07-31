import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test(
    'late authentication from an obsolete connection cannot write to the current socket',
    () async {
      final auth = _ControlledAuthService();
      final sockets = <_ControlledWebSocket>[];
      final service = ReverbService(
        notificationApi: auth,
        channelFactory: (_) {
          final socket = _ControlledWebSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(service.disconnect);

      await service.connect(
        session: _session('private-source-a'),
        credentials: _credentials('source-a'),
        onNotification: (_) {},
      );
      sockets.single.addConnectionEstablished('socket-a');
      await auth.sourceAStarted.future;

      await service.connect(
        session: _session('private-source-b'),
        credentials: _credentials('source-b'),
        onNotification: (_) {},
      );
      sockets.last.addConnectionEstablished('socket-b');
      await auth.sourceBCompleted.future;
      auth.releaseSourceA.complete();
      await auth.sourceACompleted.future;
      await Future<void>.delayed(Duration.zero);

      expect(sockets, hasLength(2));
      expect(sockets.first.sent, isEmpty);
      expect(sockets.last.sent.map(_subscriptionChannel), <String>[
        'private-source-b',
      ]);
    },
  );

  test(
    'late authentication failure cannot disconnect the current socket',
    () async {
      final auth = _ControlledAuthService(failSourceA: true);
      final sockets = <_ControlledWebSocket>[];
      final service = ReverbService(
        notificationApi: auth,
        channelFactory: (_) {
          final socket = _ControlledWebSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(service.disconnect);
      var sourceBConnected = false;

      await service.connect(
        session: _session('private-source-a'),
        credentials: _credentials('source-a'),
        onNotification: (_) {},
      );
      sockets.single.addConnectionEstablished('socket-a');
      await auth.sourceAStarted.future;

      await service.connect(
        session: _session('private-source-b'),
        credentials: _credentials('source-b'),
        onNotification: (_) {},
        onConnected: () => sourceBConnected = true,
      );
      sockets.last.addConnectionEstablished('socket-b');
      await auth.sourceBCompleted.future;
      auth.releaseSourceA.complete();
      await auth.sourceACompleted.future;
      await Future<void>.delayed(Duration.zero);
      sockets.last.addSubscriptionSucceeded();
      await Future<void>.delayed(Duration.zero);

      expect(sourceBConnected, isTrue);
      expect(sockets.last.sent.map(_subscriptionChannel), <String>[
        'private-source-b',
      ]);
    },
  );
}

const _reverb = ReverbConfig(
  host: 'fixture.invalid',
  port: 443,
  scheme: 'wss',
  appKey: 'fixture-key',
);

TvPlaylistSession _session(String channelName) => TvPlaylistSession(
  notifiableId: 1,
  notifiableType: 'playlist',
  isAdmin: false,
  channelName: channelName,
  reverb: _reverb,
);

UserCredentials _credentials(String username) => UserCredentials(
  server: 'https://fixture.invalid',
  username: username,
  password: 'private-value',
);

String _subscriptionChannel(String raw) {
  final payload = jsonDecode(raw) as Map<String, Object?>;
  final data = payload['data']! as Map<String, Object?>;
  return data['channel']! as String;
}

class _ControlledAuthService extends TvNotificationService {
  _ControlledAuthService({this.failSourceA = false});

  final bool failSourceA;
  final sourceAStarted = Completer<void>();
  final sourceACompleted = Completer<void>();
  final sourceBCompleted = Completer<void>();
  final releaseSourceA = Completer<void>();

  @override
  Future<String> broadcastAuth(
    UserCredentials creds, {
    required String socketId,
    required String channelName,
  }) async {
    if (creds.username == 'source-a') {
      sourceAStarted.complete();
      await releaseSourceA.future;
      sourceACompleted.complete();
      if (failSourceA) throw StateError('source A auth failed');
      return 'auth-a';
    }
    sourceBCompleted.complete();
    return 'auth-b';
  }
}

class _ControlledWebSocket implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  final sent = <String>[];
  late final WebSocketSink _sink = _RecordingWebSocketSink(sent);

  void addConnectionEstablished(String socketId) {
    _incoming.add(
      jsonEncode(<String, Object?>{
        'event': 'pusher:connection_established',
        'data': jsonEncode(<String, Object?>{'socket_id': socketId}),
      }),
    );
  }

  void addSubscriptionSucceeded() {
    _incoming.add(
      jsonEncode(<String, Object?>{
        'event': 'pusher_internal:subscription_succeeded',
        'data': <String, Object?>{},
      }),
    );
  }

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingWebSocketSink implements WebSocketSink {
  _RecordingWebSocketSink(this.sent);

  final List<String> sent;
  final _done = Completer<void>();

  @override
  Future<void> get done => _done.future;

  @override
  void add(dynamic data) => sent.add(data as String);

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
}
