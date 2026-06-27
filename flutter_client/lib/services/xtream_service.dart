// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_http_transport_stub.dart'
    if (dart.library.io) 'xtream_http_transport_io.dart';

typedef XtreamTransport = Future<Object?> Function(XtreamRequest request);

enum AuthErrorCode { invalidCredentials, expired, serverError, notM3UEditor }

const serverUnavailableMessage = 'Server is currently unavailable.';

class XtreamAuthException implements Exception {
  const XtreamAuthException(this.code, this.message);

  final AuthErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class XtreamHttpException implements Exception {
  const XtreamHttpException({
    required this.statusCode,
    required this.method,
    required this.uri,
    this.reasonPhrase,
    this.serverMessage,
  });

  final int statusCode;
  final String method;
  final Uri uri;
  final String? reasonPhrase;
  final String? serverMessage;

  @override
  String toString() {
    final action = uri.queryParameters['action'];
    final safeUri = uri.replace(
      queryParameters: <String, String>{'action': ?action},
    );
    final serverDetail = serverMessage == null || serverMessage!.isEmpty
        ? ''
        : ': $serverMessage';
    final reason = reasonPhrase == null || reasonPhrase!.isEmpty
        ? ''
        : ' $reasonPhrase';
    return 'Xtream HTTP $statusCode$reason for $method $safeUri$serverDetail';
  }
}

String userFacingXtreamError(Object error) {
  if (error is XtreamHttpException && error.isServerUnavailable) {
    return serverUnavailableMessage;
  }
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('connection refused') ||
      lower.contains('connection timed out') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable')) {
    return serverUnavailableMessage;
  }
  return message;
}

extension XtreamHttpExceptionClassification on XtreamHttpException {
  bool get isServerUnavailable =>
      statusCode == 502 || statusCode == 503 || statusCode == 504;
}

class XtreamResponseException implements Exception {
  const XtreamResponseException({
    required this.method,
    required this.uri,
    this.serverMessage,
  });

  final String method;
  final Uri uri;
  final String? serverMessage;

  @override
  String toString() {
    final detail = serverMessage == null || serverMessage!.isEmpty
        ? 'Server returned an invalid Xtream response.'
        : 'Server returned an invalid Xtream response: $serverMessage';
    final action = uri.queryParameters['action'];
    final safeUri = uri.replace(
      queryParameters: <String, String>{'action': ?action},
    );
    return '$detail ($method $safeUri)';
  }
}

class XtreamRequest {
  const XtreamRequest({
    required this.credentials,
    required this.headers,
    this.action,
    this.params = const {},
    this.body = const {},
    this.method = 'GET',
  });

  final UserCredentials credentials;
  final String? action;
  final Map<String, String> params;
  final Map<String, String> body;
  final Map<String, String> headers;
  final String method;

  Map<String, Object?> toDebugMap() => {
    'server': credentials.server,
    'action': action,
    'params': params,
    'body': body,
    'method': method,
  };
}

class XtreamAuthResponse {
  const XtreamAuthResponse({
    required this.isAuthenticated,
    this.status,
    this.m3uEditorVersion,
  });

  final bool isAuthenticated;
  final String? status;
  final String? m3uEditorVersion;
}

class XtreamService {
  XtreamService({XtreamTransport? transport, CacheService? cache})
    : _transport = transport ?? createDefaultXtreamTransport(),
      _cache = cache;

  static const _clientHeader = 'X-M3UE-Client';
  static const _clientValue = 'm3u-tv';
  static const _epgBatchSize = 100;

  final XtreamTransport _transport;
  final CacheService? _cache;
  UserCredentials? _credentials;
  bool _isM3UEditor = false;

  bool get isConfigured => _credentials != null;

  UserCredentials? get credentials => _credentials;

  Future<XtreamAuthResponse> authenticate(UserCredentials credentials) async {
    final normalized = credentials.normalized();
    final response = await _requestWithCredentials(
      normalized,
      null,
      headers: const {_clientHeader: _clientValue},
    );
    final json = _asMap(response);

    if (json.containsKey('error')) {
      throw XtreamAuthException(AuthErrorCode.serverError, '${json['error']}');
    }

    final userInfo = _asMap(json['user_info']);
    final auth = _asInt(userInfo['auth']);
    final status = '${userInfo['status'] ?? userInfo['message'] ?? ''}';
    if (auth != 1) {
      final code = status.toLowerCase().contains('exp')
          ? AuthErrorCode.expired
          : AuthErrorCode.invalidCredentials;
      throw XtreamAuthException(
        code,
        status.isEmpty ? 'Authentication failed' : status,
      );
    }

    final m3uEditor = json['m3u_editor'];
    if (m3uEditor is! Map) {
      throw const XtreamAuthException(
        AuthErrorCode.notM3UEditor,
        'This app requires an m3u-editor backend.',
      );
    }

    _credentials = normalized;
    _isM3UEditor = true;
    return XtreamAuthResponse(
      isAuthenticated: true,
      status: status,
      m3uEditorVersion: '${m3uEditor['version'] ?? ''}',
    );
  }

  void clearCredentials() {
    _credentials = null;
    _isM3UEditor = false;
  }

  Future<List<Category>> getLiveCategories() async =>
      _categories('get_live_categories');
  Future<List<Category>> getVodCategories() async =>
      _categories('get_vod_categories');
  Future<List<Category>> getSeriesCategories() async =>
      _categories('get_series_categories');

  Future<List<Channel>> getLiveStreams({String? categoryId}) async {
    final response = await _request(
      'get_live_streams',
      params: {'category_id': ?categoryId},
    );
    return _asList(response)
        .map((item) {
          final json = _asMap(item);
          final id = _asInt(json['stream_id']);
          return Channel.fromXtream(json, getLiveStreamUrl(id));
        })
        .toList(growable: false);
  }

  Future<List<VodItem>> getVodStreams({String? categoryId}) async {
    final response = await _request(
      'get_vod_streams',
      params: {'category_id': ?categoryId},
    );
    return _asList(response)
        .map((item) {
          final json = _asMap(item);
          final id = _asInt(json['stream_id']);
          final extension = '${json['container_extension'] ?? 'mp4'}';
          return VodItem.fromXtream(json, getVodStreamUrl(id, extension));
        })
        .toList(growable: false);
  }

  Future<VodInfo> getVodInfo(int vodId) async {
    final response = await _request(
      'get_vod_info',
      params: {'vod_id': '$vodId'},
    );
    return VodInfo.fromXtream(_asMap(response));
  }

  Future<List<Series>> getSeries({String? categoryId}) async {
    final response = await _request(
      'get_series',
      params: {'category_id': ?categoryId},
    );
    return _asList(
      response,
    ).map((item) => Series.fromXtream(_asMap(item))).toList(growable: false);
  }

  Future<SeriesInfo> getSeriesInfo(int seriesId) async {
    final response = await _request(
      'get_series_info',
      params: {'series_id': '$seriesId'},
    );
    final json = _asMap(response);
    final series = Series.fromXtream(_asMap(json['info']));
    final seasons = _asList(
      json['seasons'],
    ).map((item) => Season.fromXtream(_asMap(item))).toList();
    final episodeMap = <int, List<Episode>>{};
    final rawEpisodes = _asMap(json['episodes']);
    for (final entry in rawEpisodes.entries) {
      final seasonNumber = int.tryParse(entry.key) ?? 0;
      episodeMap[seasonNumber] = _asList(entry.value)
          .map((item) {
            final map = _asMap(item);
            final episode = Episode.fromXtream(
              map,
              streamUrl: getSeriesStreamUrl(
                '${map['id'] ?? ''}',
                '${map['container_extension'] ?? 'mp4'}',
              ),
            );
            if (episode.seasonNumber != 0) return episode;
            return Episode(
              id: episode.id,
              episodeNumber: episode.episodeNumber,
              title: episode.title,
              containerExtension: episode.containerExtension,
              seasonNumber: seasonNumber,
              plot: episode.plot,
              thumbnailUrl: episode.thumbnailUrl,
              rating: episode.rating,
              duration: episode.duration,
              releaseDate: episode.releaseDate,
              streamUrl: episode.streamUrl,
            );
          })
          .toList(growable: false);
    }
    final resolvedSeasons = seasons.isNotEmpty
        ? seasons
        : episodeMap.keys
              .map(
                (number) => Season(
                  number: number,
                  name: 'Season $number',
                  episodeCount: episodeMap[number]!.length,
                ),
              )
              .toList();
    return SeriesInfo(
      series: series,
      seasons: resolvedSeasons,
      episodesBySeason: episodeMap,
    );
  }

  Future<List<Viewer>> getViewers() async => _asList(
    await _request('get_viewers'),
  ).map((item) => Viewer.fromJson(_asMap(item))).toList(growable: false);

  Future<Viewer> createViewer(String name) async => Viewer.fromJson(
    _asMap(
      await _request('create_viewer', method: 'POST', body: {'name': name}),
    ),
  );

  Future<Progress?> getProgress(
    String viewerId,
    ContentType contentType,
    int streamId,
  ) async {
    final response = await _request(
      'get_progress',
      params: {
        'viewer_id': viewerId,
        'content_type': contentType.wireName,
        'stream_id': '$streamId',
      },
    );
    if (response == null) return null;
    return Progress.fromJson(_asMap(response), viewerId: viewerId);
  }

  Future<void> updateProgress(Progress progress) async {
    await _request(
      'update_progress',
      method: 'POST',
      body: progress.toJson().map((key, value) => MapEntry(key, '$value')),
    );
  }

  Future<List<Progress>> getSeriesProgress(
    String viewerId,
    int seriesId,
  ) async {
    final response = await _request(
      'get_series_progress',
      params: {'viewer_id': viewerId, 'series_id': '$seriesId'},
    );
    return _asList(response)
        .map((item) => Progress.fromJson(_asMap(item), viewerId: viewerId))
        .toList(growable: false);
  }

  Future<List<Progress>> getRecentlyWatched(
    String viewerId, {
    ContentType? type,
    int limit = 20,
  }) async {
    final response = await _request(
      'get_recently_watched',
      params: {
        'viewer_id': viewerId,
        'limit': '$limit',
        if (type != null) 'type': type.wireName,
      },
    );
    return _asList(response)
        .map((item) => Progress.fromJson(_asMap(item), viewerId: viewerId))
        .toList(growable: false);
  }

  Future<List<EpgProgram>> getShortEpg(
    int streamId, {
    String? channelId,
    int limit = 8,
  }) async {
    final response = await _request(
      'get_short_epg',
      params: {'stream_id': '$streamId', 'limit': '$limit'},
    );
    return _parseEpgPrograms(
      response,
      fallbackChannelId: channelId ?? '$streamId',
    );
  }

  Future<List<EpgProgram>> getEpgBatch(
    List<Channel> channels, {
    int limit = 8,
  }) async {
    if (channels.isEmpty) return const <EpgProgram>[];
    final programs = <EpgProgram>[];
    for (var start = 0; start < channels.length; start += _epgBatchSize) {
      final chunk = channels
          .skip(start)
          .take(_epgBatchSize)
          .toList(growable: false);
      final response = await _request(
        'get_epg_batch',
        params: {
          'stream_ids': chunk.map((channel) => '${channel.id}').join(','),
          'limit': '$limit',
        },
      );
      final channelIdsByStream = <String, String>{
        for (final channel in chunk)
          '${channel.id}':
              channel.epgChannelId ?? channel.tvgName ?? channel.name,
      };
      programs.addAll(
        _parseEpgPrograms(response, channelIdsByStream: channelIdsByStream),
      );
    }
    programs.sort((a, b) => a.start.compareTo(b.start));
    return programs;
  }

  String getLiveStreamUrl(int streamId, {String format = 'm3u8'}) {
    final c = _requireCredentials();
    return '${c.server}/live/${c.username}/${c.password}/$streamId.$format';
  }

  String getCatchupStreamUrl(
    int streamId,
    DateTime start,
    Duration duration, {
    String extension = 'ts',
  }) {
    final c = _requireCredentials();
    final normalizedStart = start.toUtc();
    final startText = _formatTimeshiftStart(normalizedStart);
    final durationMinutes = duration.inMinutes;
    return '${c.server}/timeshift/${c.username}/${c.password}/$durationMinutes/$startText/$streamId.$extension';
  }

  String getVodStreamUrl(int streamId, [String extension = 'mp4']) {
    final c = _requireCredentials();
    return '${c.server}/movie/${c.username}/${c.password}/$streamId.$extension';
  }

  String getSeriesStreamUrl(String episodeId, [String extension = 'mp4']) {
    final c = _requireCredentials();
    return '${c.server}/series/${c.username}/${c.password}/$episodeId.$extension';
  }

  Future<List<Category>> _categories(String action) async {
    final response = await _request(action);
    final categories = _asList(
      response,
    ).map((item) => Category.fromXtream(_asMap(item))).toList(growable: false);
    if (action == 'get_live_categories') {
      await _cache?.set('liveCategories', categories);
    }
    return categories;
  }

  Future<Object?> _request(
    String action, {
    Map<String, String> params = const {},
    Map<String, String> body = const {},
    String method = 'GET',
  }) {
    return _requestWithCredentials(
      _requireCredentials(),
      action,
      params: params,
      body: body,
      method: method,
    );
  }

  Future<Object?> _requestWithCredentials(
    UserCredentials credentials,
    String? action, {
    Map<String, String> params = const {},
    Map<String, String> body = const {},
    Map<String, String> headers = const {},
    String method = 'GET',
  }) {
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      if (_isM3UEditor) _clientHeader: _clientValue,
      ...headers,
    };
    return _transport(
      XtreamRequest(
        credentials: credentials,
        action: action,
        params: params,
        body: body,
        headers: requestHeaders,
        method: method,
      ),
    );
  }

  UserCredentials _requireCredentials() {
    final credentials = _credentials;
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    return credentials;
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const <String, Object?>{};
}

List<Object?> _asList(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

List<EpgProgram> _parseEpgPrograms(
  Object? response, {
  String? fallbackChannelId,
  Map<String, String> channelIdsByStream = const <String, String>{},
}) {
  final programs = <EpgProgram>[];
  void addPrograms(Object? raw, String? channelId) {
    for (final item in _epgListingList(raw)) {
      final program = _epgProgramFromMap(
        _asMap(item),
        channelId,
        channelIdsByStream,
      );
      if (program != null) programs.add(program);
    }
  }

  if (response is Map) {
    final json = response.cast<String, Object?>();
    final listings =
        json['epg_listings'] ??
        json['listings'] ??
        json['programmes'] ??
        json['programs'];
    if (listings != null) {
      addPrograms(listings, fallbackChannelId);
    } else {
      for (final entry in json.entries) {
        final resolved = channelIdsByStream[entry.key] ?? entry.key;
        addPrograms(entry.value, resolved);
      }
    }
  } else {
    addPrograms(response, fallbackChannelId);
  }
  programs.sort((a, b) => a.start.compareTo(b.start));
  return programs;
}

List<Object?> _epgListingList(Object? value) {
  if (value is List) return value.cast<Object?>();
  if (value is Map) {
    final json = value.cast<String, Object?>();
    return _asList(
      json['epg_listings'] ??
          json['listings'] ??
          json['programmes'] ??
          json['programs'],
    );
  }
  return const <Object?>[];
}

EpgProgram? _epgProgramFromMap(
  Map<String, Object?> json,
  String? fallbackChannelId,
  Map<String, String> channelIdsByStream,
) {
  final streamId = _stringOrNull(json['stream_id']);
  // Prefer the caller-resolved key (fallbackChannelId, derived from the
  // stream→channel mapping) so that EpgService stores programs under the same
  // key that lookupForChannel() will later use.  The program's own channel_id
  // field refers to the EPG source's internal ID, which differs from the TVG
  // ID carried in channel.epgChannelId and is therefore useless for lookups.
  final channelId =
      fallbackChannelId ??
      _stringOrNull(json['channel_id']) ??
      _stringOrNull(json['epg_channel_id']) ??
      (streamId == null ? null : channelIdsByStream[streamId]);
  if (channelId == null || channelId.isEmpty) return null;
  final start = _parseEpgTime(
    json['start_timestamp'] ?? json['start'] ?? json['start_time'],
  );
  final end = _parseEpgTime(
    json['stop_timestamp'] ??
        json['end_timestamp'] ??
        json['end'] ??
        json['stop'] ??
        json['end_time'],
  );
  if (start == null || end == null || !end.isAfter(start)) return null;
  return EpgProgram(
    channelId: channelId,
    title: _decodeBase64WhenApplicable(
      _stringOrNull(json['title']) ?? _stringOrNull(json['name']) ?? '',
    ),
    description: _decodeBase64WhenApplicable(
      _stringOrNull(json['description']) ?? _stringOrNull(json['desc']) ?? '',
    ),
    start: start,
    end: end,
  );
}

DateTime? _parseEpgTime(Object? value) {
  if (value == null) return null;
  if (value is int) return _fromEpoch(value);
  if (value is num) return _fromEpoch(value.toInt());
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) return _fromEpoch(numeric);
  final parsed = DateTime.tryParse(text);
  if (parsed != null) return parsed.isUtc ? parsed : parsed.toUtc();
  final xtream = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(text);
  if (xtream == null) return null;
  return DateTime.utc(
    int.parse(xtream.group(1)!),
    int.parse(xtream.group(2)!),
    int.parse(xtream.group(3)!),
    int.parse(xtream.group(4)!),
    int.parse(xtream.group(5)!),
    int.parse(xtream.group(6)!),
  );
}

DateTime _fromEpoch(int value) {
  final milliseconds = value > 9999999999 ? value : value * 1000;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

String _decodeBase64WhenApplicable(String value) {
  if (value.isEmpty) return value;
  final text = value.trim();
  if (text.length % 4 != 0 ||
      !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(text)) {
    return value;
  }
  try {
    final normalized = base64.normalize(text);
    final decoded = utf8.decode(
      base64.decode(normalized),
      allowMalformed: false,
    );
    return decoded.isEmpty ? value : decoded;
  } on FormatException {
    return value;
  }
}

String _formatTimeshiftStart(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  final year = value.year.toString().padLeft(4, '0');
  final month = twoDigits(value.month);
  final day = twoDigits(value.day);
  final hour = twoDigits(value.hour);
  final minute = twoDigits(value.minute);
  return '$year-$month-$day:$hour-$minute';
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text.isEmpty ? null : text;
}
