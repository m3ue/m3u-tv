import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Regression coverage for the idle-silence watchdog: Reverb tells clients
/// how long they may go without a message (`activity_timeout`) before they
/// should ping. Without a client-side heartbeat, a connection that goes
/// silently dead (no close frame ever arrives — e.g. after a laptop
/// sleep/wake or a dropped Wi-Fi hop) looks "connected" forever, so
/// dvr.status/tv.notification pushes stop arriving until the app is
/// restarted. These tests lock in:
///   1. A healthy, idle connection is NOT churned by the watchdog — the
///      reset-on-every-message path (including the server's own ping) must
///      actually prevent false reconnects.
///   2. A connection that goes completely silent past
///      activity_timeout + pong-grace forces a reconnect instead of hanging
///      forever.
void main() {
  const session = TvPlaylistSession(
    notifiableId: 1,
    notifiableType: 'playlist',
    isAdmin: false,
    channelName: 'tv.playlist.uuid-123',
    reverb: ReverbConfig(
      host: 'example.test',
      port: 6001,
      scheme: 'ws',
      appKey: 'app-key',
    ),
  );
  const credentials = UserCredentials(
    server: 'https://example.test',
    username: 'user',
    password: 'pass',
  );

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

  test(
    'healthy idle connection survives multiple activity cycles without reconnecting',
    () {
      fakeAsync((async) {
        final channels = <_FakeWebSocketChannel>[];
        final service = ReverbService(
          notificationApi: _FakeNotificationApi(),
          channelFactory: (_) {
            final channel = _FakeWebSocketChannel();
            channels.add(channel);
            return channel;
          },
        );

        unawaited(
          service.connect(
            session: session,
            credentials: credentials,
            onNotification: (_) {},
          ),
        );
        async.flushMicrotasks();
        expect(channels, hasLength(1));

        channels.single.emit(
          jsonEncode({
            'event': 'pusher:connection_established',
            'data': jsonEncode({
              'socket_id': '123.456',
              'activity_timeout': 30,
            }),
          }),
        );
        async.flushMicrotasks();

        channels.single.emit(
          jsonEncode({
            'event': 'pusher_internal:subscription_succeeded',
            'data': '{}',
          }),
        );
        async.flushMicrotasks();

        // Simulate the server's own idle ping arriving every 25s (within the
        // 30s activity_timeout) for several cycles — the connection is
        // healthy the whole time and must never be torn down.
        for (var i = 0; i < 3; i++) {
          async.elapse(const Duration(seconds: 25));
          channels.single.emit(
            jsonEncode({'event': 'pusher:ping', 'data': '{}'}),
          );
          async.flushMicrotasks();
        }

        expect(
          channels,
          hasLength(1),
          reason:
              'no reconnect should have happened while the socket '
              'kept receiving activity within each window',
        );
        expect(
          channels.single.sent,
          everyElement(isNot(contains('"pusher:ping"'))),
          reason:
              'the client should not need to self-ping when the server '
              'is already sending activity',
        );
      });
    },
  );

  test(
    'force-reconnects when the connection goes silent past the pong grace period',
    () {
      fakeAsync((async) {
        final channels = <_FakeWebSocketChannel>[];
        final service = ReverbService(
          notificationApi: _FakeNotificationApi(),
          channelFactory: (_) {
            final channel = _FakeWebSocketChannel();
            channels.add(channel);
            return channel;
          },
        );

        unawaited(
          service.connect(
            session: session,
            credentials: credentials,
            onNotification: (_) {},
          ),
        );
        async.flushMicrotasks();

        channels.single.emit(
          jsonEncode({
            'event': 'pusher:connection_established',
            'data': jsonEncode({
              'socket_id': '123.456',
              'activity_timeout': 30,
            }),
          }),
        );
        async.flushMicrotasks();

        channels.single.emit(
          jsonEncode({
            'event': 'pusher_internal:subscription_succeeded',
            'data': '{}',
          }),
        );
        // Total silence: nothing arrives at all — not the server's ping,
        // not our own reply. After activity_timeout (30s) the client
        // proactively pings; after a further 15s grace with no reply, the
        // connection is presumed dead and a reconnect is forced.
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 30));
        expect(
          channels.single.sent,
          contains(
            jsonEncode({'event': 'pusher:ping', 'data': <String, Object?>{}}),
          ),
          reason: 'client should self-ping after activity_timeout of silence',
        );

        // 15s pong grace, then _scheduleReconnect's own backoff timer (2s).
        async
          ..elapse(const Duration(seconds: 17))
          ..flushMicrotasks();

        expect(
          channels,
          hasLength(2),
          reason: 'a zombie connection must be abandoned and replaced',
        );
      });
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

class _FakeNotificationApi extends TvNotificationService {
  @override
  Future<String> broadcastAuth(
    UserCredentials creds, {
    required String socketId,
    required String channelName,
  }) async => 'fake-auth-token';
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

class _FakeWebSocketChannel
    with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<String> sent = <String>[];
  bool sinkClosed = false;

  void emit(String message) => _incoming.add(message);

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future<void>.value();
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

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeWebSocketChannel _channel;

  @override
  void add(dynamic data) => _channel.sent.add(data as String);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.sinkClosed = true;
  }

  @override
  Future<void> get done => Future<void>.value();
}
