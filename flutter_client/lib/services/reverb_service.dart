import 'dart:async';
import 'dart:convert';

import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Pusher-protocol WebSocket client for Laravel Reverb.
///
/// Connects to the private TV playlist channel, authenticates via the custom
/// `/api/tv/broadcasting/auth` endpoint (no user session required), and
/// forwards incoming `tv.notification`, `dvr.status`, `request.status`, and
/// `favorite.toggled` events to the supplied callbacks.
///
/// Call `connect` after a successful Xtream login. Call `pause`/`resume`
/// around app background/foreground transitions, and `disconnect` on logout.
/// Reconnects automatically with exponential backoff.
class ReverbService {
  ReverbService({
    TvNotificationService? notificationApi,
    WebSocketChannel Function(Uri)? channelFactory,
  }) : _api = notificationApi ?? TvNotificationService(),
       _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final TvNotificationService _api;
  final WebSocketChannel Function(Uri) _channelFactory;

  late UserCredentials _credentials;
  late TvPlaylistSession _session;
  Set<String> _subscribedChannels = const {};
  void Function(TvNotificationItem)? _onNotification;
  void Function(DvrRecording)? _onDvrStatus;
  void Function(MediaRequestSummary)? _onRequestStatus;
  void Function(FavoriteToggleEvent)? _onFavoriteToggled;
  void Function()? _onConnected;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _idleTimer;
  Timer? _pongTimer;
  bool _disposed = false;
  bool _paused = false;
  bool _connected = false;
  bool _hasConnectedBefore = false;
  int _retryDelay = 2;
  final Generation _connectionGeneration = Generation();
  int _activityTimeoutSeconds = 30;

  static const int _maxRetryDelay = 60;
  static const int _pongGraceSeconds = 15;

  /// Connects to Reverb and starts listening for push notifications.
  ///
  /// Pass a non-empty [subscribedChannels] set to filter by category; an empty
  /// set means "receive all channels".
  Future<void> connect({
    required TvPlaylistSession session,
    required UserCredentials credentials,
    Set<String> subscribedChannels = const {},
    required void Function(TvNotificationItem) onNotification,
    void Function(DvrRecording)? onDvrStatus,
    void Function(MediaRequestSummary)? onRequestStatus,
    void Function(FavoriteToggleEvent)? onFavoriteToggled,
    void Function()? onConnected,
  }) async {
    final connectionGeneration = _connectionGeneration.advance();
    final previousSubscription = _sub;
    final previousSocket = _ws;
    _idleTimer?.cancel();
    _idleTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub = null;
    _ws = null;
    _connected = false;
    _session = session;
    _credentials = credentials;
    _subscribedChannels = subscribedChannels;
    _onNotification = onNotification;
    _onDvrStatus = onDvrStatus;
    _onRequestStatus = onRequestStatus;
    _onFavoriteToggled = onFavoriteToggled;
    _onConnected = onConnected;
    _disposed = false;
    _paused = false;
    _hasConnectedBefore = true;
    _retryDelay = 2;
    await previousSubscription?.cancel();
    await previousSocket?.sink.close();
    if (_connectionGeneration.isStale(connectionGeneration)) return;
    await _connectOnce(connectionGeneration);
  }

  Future<void> _connectOnce(int connectionGeneration) async {
    if (_disposed || _connectionGeneration.isStale(connectionGeneration)) {
      return;
    }

    final session = _session;
    final creds = _credentials;

    try {
      final socket = _channelFactory(session.reverb.wsUri);
      if (_connectionGeneration.isStale(connectionGeneration)) {
        await socket.sink.close();
        return;
      }
      _ws = socket;
      _connected = false;

      _sub = socket.stream.listen(
        (raw) {
          _onMessage(
            raw as String,
            session,
            creds,
            connectionGeneration,
            socket,
          );
          _resetIdleTimer(connectionGeneration, socket);
        },
        onError: (_) => _scheduleReconnect(connectionGeneration, socket),
        onDone: () => _scheduleReconnect(connectionGeneration, socket),
        cancelOnError: true,
      );
      _resetIdleTimer(connectionGeneration, socket);
    } on Object catch (_) {
      _scheduleReconnect(connectionGeneration);
    }
  }

  /// Restarts the idle-silence watchdog. Called on every message received
  /// (proving the socket is alive) and once right after connecting.
  ///
  /// Reverb tells clients (via `activity_timeout` on `connection_established`)
  /// how long they may go without a message before they're expected to ping.
  /// If nothing at all arrives within that window — not even the server's own
  /// keep-alive — [_sendPing] probes the connection explicitly.
  void _resetIdleTimer(
    int connectionGeneration,
    WebSocketChannel socket,
  ) {
    if (_connectionGeneration.isStale(connectionGeneration) ||
        !identical(_ws, socket)) {
      return;
    }
    _pongTimer?.cancel();
    _pongTimer = null;
    _idleTimer?.cancel();
    _idleTimer = Timer(
      Duration(seconds: _activityTimeoutSeconds),
      () => _sendPing(connectionGeneration, socket),
    );
  }

  /// Probes a silent connection. If nothing (not even a reply to this ping)
  /// arrives within the grace period, the socket is a zombie the transport
  /// never reported as closed (e.g. after a laptop sleep/wake or a dropped
  /// Wi-Fi hop) — force a reconnect rather than waiting on it forever.
  void _sendPing(int connectionGeneration, WebSocketChannel socket) {
    if (_connectionGeneration.isStale(connectionGeneration) ||
        !identical(_ws, socket)) {
      return;
    }
    _send(socket, {'event': 'pusher:ping', 'data': {}});
    _pongTimer?.cancel();
    _pongTimer = Timer(
      const Duration(seconds: _pongGraceSeconds),
      () => _scheduleReconnect(connectionGeneration, socket),
    );
  }

  void _onMessage(
    String raw,
    TvPlaylistSession session,
    UserCredentials creds,
    int connectionGeneration,
    WebSocketChannel socket,
  ) {
    if (_connectionGeneration.isStale(connectionGeneration) ||
        !identical(_ws, socket)) {
      return;
    }
    final Map<String, Object?> msg;
    try {
      msg = (jsonDecode(raw) as Map).cast<String, Object?>();
    } on Object catch (_) {
      return;
    }

    final event = '${msg['event'] ?? ''}';

    switch (event) {
      case 'pusher:connection_established':
        final data = _parseData(msg['data']);
        final socketId = '${data['socket_id'] ?? ''}';
        final activityTimeout = int.tryParse('${data['activity_timeout']}');
        if (activityTimeout != null && activityTimeout > 0) {
          _activityTimeoutSeconds = activityTimeout;
        }
        if (socketId.isNotEmpty) {
          unawaited(
            _authenticate(
              session,
              creds,
              socketId,
              connectionGeneration,
              socket,
            ),
          );
        }

      case 'pusher:ping':
        _send(socket, {'event': 'pusher:pong', 'data': {}});

      case 'pusher_internal:subscription_succeeded':
        _connected = true;
        _retryDelay = 2;
        _onConnected?.call();

      case 'tv.notification':
        if (!_connected) return;
        final payload = _parseData(msg['data']);
        final item = TvNotificationItem.tryFromJson(payload);
        if (item == null) return;
        if (_subscribedChannels.isEmpty ||
            _subscribedChannels.contains(item.channel)) {
          _onNotification?.call(item);
        }

      case 'dvr.status':
        if (!_connected) return;
        final payload = _parseData(msg['data']);
        _onDvrStatus?.call(DvrRecording.fromXtream(payload));

      case 'request.status':
        if (!_connected) return;
        final payload = _parseData(msg['data']);
        _onRequestStatus?.call(MediaRequestSummary.fromJson(payload));

      case 'favorite.toggled':
        if (!_connected) return;
        final payload = _parseData(msg['data']);
        final favoriteEvent = FavoriteToggleEvent.tryFromJson(payload);
        if (favoriteEvent == null) return;
        _onFavoriteToggled?.call(favoriteEvent);
    }
  }

  Future<void> _authenticate(
    TvPlaylistSession session,
    UserCredentials creds,
    String socketId,
    int connectionGeneration,
    WebSocketChannel socket,
  ) async {
    final channelName = session.channelName;
    try {
      final auth = await _api.broadcastAuth(
        creds,
        socketId: socketId,
        channelName: channelName,
      );
      if (_connectionGeneration.isStale(connectionGeneration) ||
          !identical(_ws, socket)) {
        return;
      }
      _send(socket, {
        'event': 'pusher:subscribe',
        'data': {'auth': auth, 'channel': channelName},
      });
    } on Object catch (_) {
      _scheduleReconnect(connectionGeneration, socket);
    }
  }

  void _send(WebSocketChannel socket, Map<String, Object?> payload) {
    try {
      socket.sink.add(jsonEncode(payload));
    } on Object catch (_) {}
  }

  void _scheduleReconnect(
    int connectionGeneration, [
    WebSocketChannel? socket,
  ]) {
    if (_connectionGeneration.isStale(connectionGeneration) ||
        (socket != null && !identical(_ws, socket))) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    _sub?.cancel().ignore();
    _sub = null;
    _ws = null;
    _connected = false;
    if (_disposed || _paused) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _retryDelay), () {
      if (_disposed ||
          _paused ||
          _connectionGeneration.isStale(connectionGeneration)) {
        return;
      }
      _retryDelay = (_retryDelay * 2).clamp(2, _maxRetryDelay);
      unawaited(_connectOnce(_connectionGeneration.advance()));
    });
  }

  /// Suspends the connection while the app is backgrounded, without
  /// discarding session/credentials. Call [resume] to reconnect. Unlike
  /// [disconnect], this is not terminal — reconnect attempts resume on
  /// [resume] rather than being permanently disabled.
  Future<void> pause() async {
    if (_disposed) return;
    _connectionGeneration.advance();
    _paused = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connected = false;
    await _sub?.cancel();
    _sub = null;
    await _ws?.sink.close();
    _ws = null;
  }

  /// Reconnects after [pause], or after the socket otherwise dropped without
  /// an explicit [pause] (e.g. the OS silently killed it while backgrounded).
  /// No-op if [connect] was never called, already connected, or [disconnect]ed.
  Future<void> resume() async {
    if (_disposed || !_hasConnectedBefore || _connected) return;
    _paused = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _retryDelay = 2;
    await _connectOnce(_connectionGeneration.advance());
  }

  /// Disconnects and prevents any further reconnect attempts.
  Future<void> disconnect() async {
    _connectionGeneration.advance();
    _disposed = true;
    _paused = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connected = false;
    await _sub?.cancel();
    _sub = null;
    await _ws?.sink.close();
    _ws = null;
  }

  Map<String, Object?> _parseData(Object? raw) {
    if (raw is Map) return raw.cast<String, Object?>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, Object?>();
      } on Object catch (_) {}
    }
    return const {};
  }
}
