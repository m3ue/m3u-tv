import 'dart:async';
import 'dart:convert';

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Pusher-protocol WebSocket client for Laravel Reverb.
///
/// Connects to the private TV playlist channel, authenticates via the custom
/// `/api/tv/broadcasting/auth` endpoint (no user session required), and
/// forwards incoming `tv.notification` and `dvr.status` events to the
/// supplied callbacks.
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
  void Function()? _onConnected;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _paused = false;
  bool _connected = false;
  int _retryDelay = 2;

  static const int _maxRetryDelay = 60;

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
    void Function()? onConnected,
  }) async {
    _session = session;
    _credentials = credentials;
    _subscribedChannels = subscribedChannels;
    _onNotification = onNotification;
    _onDvrStatus = onDvrStatus;
    _onRequestStatus = onRequestStatus;
    _onConnected = onConnected;
    _disposed = false;
    _paused = false;
    _retryDelay = 2;
    await _connectOnce();
  }

  Future<void> _connectOnce() async {
    if (_disposed) return;

    final session = _session;
    final creds = _credentials;

    try {
      _ws = _channelFactory(session.reverb.wsUri);
      _connected = false;

      _sub = _ws!.stream.listen(
        (raw) => _onMessage(raw as String, session, creds),
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } on Object catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(
    String raw,
    TvPlaylistSession session,
    UserCredentials creds,
  ) {
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
        if (socketId.isNotEmpty) {
          unawaited(_authenticate(session, creds, socketId));
        }

      case 'pusher_internal:subscription_succeeded':
        _connected = true;
        _retryDelay = 2;
        _onConnected?.call();

      case 'tv.notification':
        if (!_connected) return;
        final payload = _parseData(msg['data']);
        final item = TvNotificationItem.fromJson(payload);
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
    }
  }

  Future<void> _authenticate(
    TvPlaylistSession session,
    UserCredentials creds,
    String socketId,
  ) async {
    final channelName = session.channelName;
    try {
      final auth = await _api.broadcastAuth(
        creds,
        socketId: socketId,
        channelName: channelName,
      );
      _send({
        'event': 'pusher:subscribe',
        'data': {'auth': auth, 'channel': channelName},
      });
    } on Object catch (_) {
      _scheduleReconnect();
    }
  }

  void _send(Map<String, Object?> payload) {
    try {
      _ws?.sink.add(jsonEncode(payload));
    } on Object catch (_) {}
  }

  void _scheduleReconnect() {
    _sub?.cancel().ignore();
    _sub = null;
    _ws = null;
    _connected = false;
    if (_disposed || _paused) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _retryDelay), () {
      if (_disposed || _paused) return;
      _retryDelay = (_retryDelay * 2).clamp(2, _maxRetryDelay);
      unawaited(_connectOnce());
    });
  }

  /// Suspends the connection while the app is backgrounded, without
  /// discarding session/credentials. Call [resume] to reconnect. Unlike
  /// [disconnect], this is not terminal — reconnect attempts resume on
  /// [resume] rather than being permanently disabled.
  Future<void> pause() async {
    if (_disposed) return;
    _paused = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connected = false;
    await _sub?.cancel();
    _sub = null;
    await _ws?.sink.close();
    _ws = null;
  }

  /// Reconnects a connection previously suspended by [pause]. No-op if not
  /// currently paused (e.g. never connected, or already [disconnect]ed).
  Future<void> resume() async {
    if (_disposed || !_paused) return;
    _paused = false;
    _retryDelay = 2;
    await _connectOnce();
  }

  /// Disconnects and prevents any further reconnect attempts.
  Future<void> disconnect() async {
    _disposed = true;
    _paused = false;
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
