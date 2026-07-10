// ignore_for_file: sort_constructors_first

import 'dart:convert';
import 'dart:io';

import 'package:m3u_tv/services/domain_models.dart';

/// Reverb connection config returned by the notifications endpoint.
class ReverbConfig {
  const ReverbConfig({
    required this.host,
    required this.port,
    required this.scheme,
    required this.appKey,
  });

  final String host;
  final int port;

  /// Either 'ws' or 'wss'.
  final String scheme;
  final String appKey;

  factory ReverbConfig.fromJson(Map<String, Object?> json) => ReverbConfig(
    host: '${json['host'] ?? 'localhost'}',
    port: _asInt(json['port']) == 0 ? 36800 : _asInt(json['port']),
    scheme: '${json['scheme'] ?? 'ws'}',
    appKey: '${json['app_key'] ?? ''}',
  );

  Uri get wsUri => Uri(
    scheme: scheme,
    host: host,
    port: port,
    path: '/app/$appKey',
  );
}

/// A notification channel defined in the m3u-editor settings.
class TvNotificationChannel {
  const TvNotificationChannel({required this.name, required this.label});

  /// Slug used in notification payloads (e.g. 'dvr_recording_completed').
  final String name;

  /// Human-readable label configured in the editor, or empty if not set.
  final String label;

  /// Returns [label] when non-empty, otherwise [name] with the first letter capitalised.
  String get displayName => label.isNotEmpty
      ? label
      : name.isEmpty
      ? name
      : '${name[0].toUpperCase()}${name.substring(1)}';

  factory TvNotificationChannel.fromJson(Map<String, Object?> json) =>
      TvNotificationChannel(
        name: '${json['name'] ?? ''}',
        label: '${json['label'] ?? ''}',
      );
}

/// Playlist identity returned alongside unread notifications on boot.
class TvPlaylistSession {
  const TvPlaylistSession({
    required this.notifiableId,
    required this.notifiableType,
    required this.isAdmin,
    required this.channelName,
    required this.reverb,
    this.availableChannels = const [],
  });

  final int notifiableId;
  final String notifiableType;

  /// True when authenticated via owner-auth with an admin user.
  final bool isAdmin;

  /// Server-authoritative WebSocket channel name to subscribe to.
  final String channelName;

  final ReverbConfig reverb;

  /// Notification channels configured in the editor (Settings → TV App).
  /// Empty when the server hasn't configured any, or is an older version.
  final List<TvNotificationChannel> availableChannels;
}

/// A single TV notification (from REST or WebSocket push).
class TvNotificationItem {
  const TvNotificationItem({
    required this.id,
    required this.channel,
    required this.title,
    this.body,
    required this.status,
  });

  final String id;

  /// Notification channel category: 'general', 'error', 'sync_complete', etc.
  final String channel;
  final String title;
  final String? body;

  /// 'success' | 'warning' | 'danger' | 'info'
  final String status;

  factory TvNotificationItem.fromJson(Map<String, Object?> json) {
    final rawId = json['id'];
    final id = rawId is String && rawId.isNotEmpty
        ? rawId
        : 'live-${DateTime.now().microsecondsSinceEpoch}';
    return TvNotificationItem(
      id: id,
      channel: '${json['channel'] ?? 'general'}',
      title: '${json['title'] ?? ''}',
      body: json['body'] as String?,
      status: '${json['status'] ?? 'info'}',
    );
  }
}

/// REST client for the `/api/tv` endpoints.
///
/// All methods accept [UserCredentials] directly — no session or token needed.
class TvNotificationService {
  TvNotificationService({HttpClient? httpClient})
    : _client = httpClient ?? HttpClient();

  final HttpClient _client;

  /// Fetches unread notifications and the Reverb session config.
  ///
  /// Pass [channels] to restrict which notification categories are returned.
  /// An empty or null [channels] list returns all unread notifications.
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async {
    final base = _baseUri(creds.server);
    final u = Uri.encodeComponent(creds.username);
    final p = Uri.encodeComponent(creds.password);
    final queryParams = <String, dynamic>{};
    if (channels != null && channels.isNotEmpty) {
      queryParams['channels'] = channels;
    }
    final uri = base.replace(
      path: '${base.path}/api/tv/$u/$p/notifications',
      queryParameters: queryParams.isEmpty ? null : _flattenParams(queryParams),
    );

    final response = await _get(uri);
    final json =
        (response as Map?)?.cast<String, Object?>() ?? <String, Object?>{};

    final reverbJson = (json['reverb'] as Map?)?.cast<String, Object?>() ?? {};

    final rawChannels = json['available_channels'] as List? ?? const [];
    final availableChannels = rawChannels
        .whereType<Map<String, Object?>>()
        .map(TvNotificationChannel.fromJson)
        .where((c) => c.name.isNotEmpty)
        .toList(growable: false);

    final session = TvPlaylistSession(
      notifiableId: _asInt(json['notifiable_id']),
      notifiableType: '${json['notifiable_type'] ?? ''}',
      isAdmin: json['is_admin'] == true,
      channelName: '${reverbJson['channel'] ?? ''}',
      reverb: ReverbConfig.fromJson(reverbJson),
      availableChannels: availableChannels,
    );

    final rawList = json['notifications'] as List? ?? const [];
    final notifications = rawList
        .whereType<Map<String, Object?>>()
        .map(TvNotificationItem.fromJson)
        .toList(growable: false);

    return (session, notifications);
  }

  /// Marks a single notification as read.
  Future<void> markRead(UserCredentials creds, String id) async {
    final base = _baseUri(creds.server);
    final u = Uri.encodeComponent(creds.username);
    final p = Uri.encodeComponent(creds.password);
    final uri = base.replace(
      path: '${base.path}/api/tv/$u/$p/notifications/$id/read',
    );
    await _post(uri, {});
  }

  /// Obtains a Pusher HMAC auth token for [channelName].
  Future<String> broadcastAuth(
    UserCredentials creds, {
    required String socketId,
    required String channelName,
  }) async {
    final base = _baseUri(creds.server);
    final u = Uri.encodeComponent(creds.username);
    final p = Uri.encodeComponent(creds.password);
    final uri = base.replace(
      path: '${base.path}/api/tv/$u/$p/broadcasting/auth',
    );
    final body = await _post(uri, {
      'socket_id': socketId,
      'channel_name': channelName,
    });
    final map = body as Map<String, Object?>? ?? {};
    return '${map['auth'] ?? ''}';
  }

  // ---- helpers ----

  Uri _baseUri(String server) {
    final uri = Uri.parse(server.replaceAll(RegExp(r'/+$'), ''));
    // Strip /player_api.php if the server URL includes it.
    final path = uri.path.endsWith('/player_api.php')
        ? uri.path.substring(0, uri.path.length - '/player_api.php'.length)
        : uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri.replace(path: path, queryParameters: <String, String>{});
  }

  Future<Object?> _get(Uri uri) async {
    final request = await _client.getUrl(uri);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw TvApiException(response.statusCode, text, uri);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<Object?> _post(Uri uri, Map<String, String> body) async {
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
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// Converts nested list params to repeated key form for GET queries.
  Map<String, String> _flattenParams(Map<String, dynamic> params) {
    final result = <String, String>{};
    for (final entry in params.entries) {
      if (entry.value is List) {
        final list = entry.value as List;
        for (var i = 0; i < list.length; i++) {
          result['${entry.key}[$i]'] = '${list[i]}';
        }
      } else {
        result[entry.key] = '${entry.value}';
      }
    }
    return result;
  }
}

class TvApiException implements Exception {
  const TvApiException(this.statusCode, this.body, this.uri);

  final int statusCode;
  final String body;
  final Uri uri;

  @override
  String toString() => 'TvApiException($statusCode) ${uri.path}: $body';
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
