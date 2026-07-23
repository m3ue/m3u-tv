import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/tv_notification_service.dart'
    show TvApiException;

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
  PushNotificationService({HttpClient? httpClient})
    : _client = httpClient ?? HttpClient();

  final HttpClient _client;

  /// Initializes Firebase, requests notification permission, and returns the
  /// device's FCM registration token (or null if permission was denied).
  Future<String?> init({FirebaseOptions? options}) async {
    await Firebase.initializeApp(options: options);

    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }

    return FirebaseMessaging.instance.getToken();
  }

  /// Fires whenever Firebase rotates the device's FCM token; callers should
  /// re-register with [registerToken] each time this emits.
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  /// Registers [token] with the self-hosted m3u-editor instance so it can
  /// forward pushes through the m3u-push-relay.
  ///
  /// Mirrors `TvNotificationService`'s no-session REST convention. The
  /// backend endpoint (`POST /api/tv/{u}/{p}/push/subscribe`) is Phase 3 of
  /// the push-notifications plan and doesn't exist yet — this will 404 until
  /// then.
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
}
