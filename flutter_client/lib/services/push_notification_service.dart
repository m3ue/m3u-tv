import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/tv_notification_service.dart'
    show TvApiException, canonicalNotificationId;

typedef PushMessageHandler = FutureOr<void> Function(PushMessage message);

class PushMessage {
  const PushMessage({required this.data});

  final Map<String, String> data;

  String? get notificationId => canonicalNotificationId(
    data['notification_id'],
  );
}

abstract interface class PushMessagingClient {
  Future<void> initialize();

  Future<bool> requestPermission();

  Future<String?> getToken();

  Stream<String> get onTokenRefresh;

  Stream<PushMessage> get onForegroundMessage;

  Stream<PushMessage> get onMessageOpenedApp;

  Future<PushMessage?> getInitialMessage();
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebasePushMessagingClient({this.options});

  final FirebaseOptions? options;

  @override
  Future<void> initialize() => Firebase.initializeApp(options: options);

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus != AuthorizationStatus.denied;
  }

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_fromRemoteMessage);

  @override
  Stream<PushMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_fromRemoteMessage);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : _fromRemoteMessage(message);
  }

  PushMessage _fromRemoteMessage(RemoteMessage message) => PushMessage(
    data: message.data.map(
      (key, value) => MapEntry(key, '$value'),
    ),
  );
}

/// Mobile-only push notifications via Firebase Cloud Messaging.
///
/// Not used on TV builds (Android TV, tvOS) — those rely on the existing
/// Reverb WebSocket pipeline (`ReverbConfig` / `TvNotificationService`) for
/// in-app delivery while the app is open. Callers must gate use of this
/// service to phone/tablet device types themselves (see `DeviceType` in
/// `app/app_shell.dart`).
///
/// Requires `flutterfire configure` to have generated `firebase_options.dart`
/// (or the equivalent native `google-services.json` /
/// `GoogleService-Info.plist`) before [init] is called — until then, calling
/// [init] throws.
class PushNotificationService {
  PushNotificationService({
    HttpClient? httpClient,
    PushMessagingClient? messagingClient,
  }) : _client = httpClient ?? HttpClient(),
       _messagingClient = messagingClient ?? FirebasePushMessagingClient();

  final HttpClient _client;
  final PushMessagingClient _messagingClient;
  Future<String?>? _initialization;
  StreamSubscription<PushMessage>? _foregroundSubscription;
  StreamSubscription<PushMessage>? _openedSubscription;

  /// Initializes Firebase, requests notification permission, and returns the
  /// device's FCM registration token (or null if permission was denied).
  Future<String?> init({
    required PushMessageHandler onForegroundMessage,
    required PushMessageHandler onMessageOpenedApp,
  }) {
    return _initialization ??= _initialize(
      onForegroundMessage: onForegroundMessage,
      onMessageOpenedApp: onMessageOpenedApp,
    );
  }

  Future<String?> _initialize({
    required PushMessageHandler onForegroundMessage,
    required PushMessageHandler onMessageOpenedApp,
  }) async {
    await _messagingClient.initialize();
    if (!await _messagingClient.requestPermission()) return null;

    _foregroundSubscription = _messagingClient.onForegroundMessage.listen(
      (message) => unawaited(Future.sync(() => onForegroundMessage(message))),
    );
    _openedSubscription = _messagingClient.onMessageOpenedApp.listen(
      (message) => unawaited(Future.sync(() => onMessageOpenedApp(message))),
    );
    final initialMessage = await _messagingClient.getInitialMessage();
    if (initialMessage != null) {
      await onMessageOpenedApp(initialMessage);
    }
    return _messagingClient.getToken();
  }

  /// Fires whenever Firebase rotates the device's FCM token; callers should
  /// re-register with [registerToken] each time this emits.
  Stream<String> get onTokenRefresh => _messagingClient.onTokenRefresh;

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }

  /// Registers [token] with the self-hosted m3u-editor instance so it can
  /// forward pushes through the m3u-push-relay.
  ///
  /// Mirrors `TvNotificationService`'s requester-scoped, no-session REST
  /// convention.
  Future<void> registerToken(
    UserCredentials creds, {
    required String token,
    required String platform,
  }) async {
    final base = _baseUri(creds.server);
    final u = Uri.encodeComponent(creds.username);
    final p = Uri.encodeComponent(creds.password);
    final uri = base.replace(path: '${base.path}/api/tv/$u/$p/push/subscribe');
    await _post(uri, {'token': token, 'platform': platform});
  }

  Future<void> unregisterToken(
    UserCredentials creds, {
    required String token,
  }) async {
    final base = _baseUri(creds.server);
    final u = Uri.encodeComponent(creds.username);
    final p = Uri.encodeComponent(creds.password);
    final uri = base.replace(
      path: '${base.path}/api/tv/$u/$p/push/unsubscribe',
    );
    await _delete(uri, {'token': token});
  }

  Uri _baseUri(String server) {
    final uri = Uri.parse(server.replaceAll(RegExp(r'/+$'), ''));
    final path = uri.path.endsWith('/player_api.php')
        ? uri.path.substring(0, uri.path.length - '/player_api.php'.length)
        : uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri.replace(path: path, queryParameters: <String, String>{});
  }

  Future<void> _post(Uri uri, Map<String, String> body) async {
    final request = await _client.postUrl(uri);
    final bytes = utf8.encode(jsonEncode(body));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request
      ..contentLength = bytes.length
      ..add(bytes);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw TvApiException(response.statusCode, text, uri);
    }
  }

  Future<void> _delete(Uri uri, Map<String, String> body) async {
    final request = await _client.deleteUrl(uri);
    final bytes = utf8.encode(jsonEncode(body));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request
      ..contentLength = bytes.length
      ..add(bytes);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw TvApiException(response.statusCode, text, uri);
    }
  }
}
