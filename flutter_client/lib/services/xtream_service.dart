// ignore_for_file: prefer_initializing_formals

import 'cache_service.dart';
import 'domain_models.dart';
import 'xtream_http_transport_stub.dart'
    if (dart.library.io) 'xtream_http_transport_io.dart';

typedef XtreamTransport = Future<Object?> Function(XtreamRequest request);

enum AuthErrorCode { invalidCredentials, expired, serverError, notM3UEditor }

class XtreamAuthException implements Exception {
  const XtreamAuthException(this.code, this.message);

  final AuthErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class XtreamRequest {
  const XtreamRequest({required this.credentials, required this.headers, this.action, this.params = const {}, this.body = const {}, this.method = 'GET'});

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
  const XtreamAuthResponse({required this.isAuthenticated, this.status, this.m3uEditorVersion});

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

  final XtreamTransport _transport;
  final CacheService? _cache;
  UserCredentials? _credentials;
  bool _isM3UEditor = false;

  bool get isConfigured => _credentials != null;

  UserCredentials? get credentials => _credentials;

  Future<XtreamAuthResponse> authenticate(UserCredentials credentials) async {
    final normalized = credentials.normalized();
    final response = await _requestWithCredentials(normalized, null, headers: const {_clientHeader: _clientValue});
    final json = _asMap(response);

    if (json.containsKey('error')) {
      throw XtreamAuthException(AuthErrorCode.serverError, '${json['error']}');
    }

    final userInfo = _asMap(json['user_info']);
    final auth = _asInt(userInfo['auth']);
    final status = '${userInfo['status'] ?? userInfo['message'] ?? ''}';
    if (auth != 1) {
      final code = status.toLowerCase().contains('exp') ? AuthErrorCode.expired : AuthErrorCode.invalidCredentials;
      throw XtreamAuthException(code, status.isEmpty ? 'Authentication failed' : status);
    }

    final m3uEditor = json['m3u_editor'];
    if (m3uEditor is! Map) {
      throw const XtreamAuthException(AuthErrorCode.notM3UEditor, 'This app requires an m3u-editor backend.');
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

  Future<List<Category>> getLiveCategories() async => _categories('get_live_categories');
  Future<List<Category>> getVodCategories() async => _categories('get_vod_categories');
  Future<List<Category>> getSeriesCategories() async => _categories('get_series_categories');

  Future<List<Channel>> getLiveStreams({String? categoryId}) async {
    final response = await _request('get_live_streams', params: {if (categoryId != null) 'category_id': categoryId});
    return _asList(response).map((item) {
      final json = _asMap(item);
      final id = _asInt(json['stream_id']);
      return Channel.fromXtream(json, getLiveStreamUrl(id));
    }).toList(growable: false);
  }

  Future<List<VodItem>> getVodStreams({String? categoryId}) async {
    final response = await _request('get_vod_streams', params: {if (categoryId != null) 'category_id': categoryId});
    return _asList(response).map((item) {
      final json = _asMap(item);
      final id = _asInt(json['stream_id']);
      final extension = '${json['container_extension'] ?? 'mp4'}';
      return VodItem.fromXtream(json, getVodStreamUrl(id, extension));
    }).toList(growable: false);
  }

  Future<List<Series>> getSeries({String? categoryId}) async {
    final response = await _request('get_series', params: {if (categoryId != null) 'category_id': categoryId});
    return _asList(response).map((item) => Series.fromXtream(_asMap(item))).toList(growable: false);
  }

  Future<SeriesInfo> getSeriesInfo(int seriesId) async {
    final response = await _request('get_series_info', params: {'series_id': '$seriesId'});
    final json = _asMap(response);
    final series = Series.fromXtream(_asMap(json['info']));
    final seasons = _asList(json['seasons']).map((item) => Season.fromXtream(_asMap(item))).toList();
    final episodeMap = <int, List<Episode>>{};
    final rawEpisodes = _asMap(json['episodes']);
    for (final entry in rawEpisodes.entries) {
      final seasonNumber = int.tryParse(entry.key) ?? 0;
      episodeMap[seasonNumber] = _asList(entry.value).map((item) {
        final episode = Episode.fromXtream(_asMap(item));
        return Episode(
          id: episode.id,
          episodeNumber: episode.episodeNumber,
          title: episode.title,
          containerExtension: episode.containerExtension,
          seasonNumber: episode.seasonNumber == 0 ? seasonNumber : episode.seasonNumber,
          plot: episode.plot,
          streamUrl: getSeriesStreamUrl(episode.id, episode.containerExtension),
        );
      }).toList(growable: false);
    }
    final resolvedSeasons = seasons.isNotEmpty
        ? seasons
        : episodeMap.keys.map((number) => Season(number: number, name: 'Season $number', episodeCount: episodeMap[number]!.length)).toList();
    return SeriesInfo(series: series, seasons: resolvedSeasons, episodesBySeason: episodeMap);
  }

  Future<List<Viewer>> getViewers() async => _asList(await _request('get_viewers')).map((item) => Viewer.fromJson(_asMap(item))).toList(growable: false);

  Future<Viewer> createViewer(String name) async => Viewer.fromJson(_asMap(await _request('create_viewer', method: 'POST', body: {'name': name})));

  Future<Progress?> getProgress(String viewerId, ContentType contentType, int streamId) async {
    final response = await _request('get_progress', params: {'viewer_id': viewerId, 'content_type': contentType.wireName, 'stream_id': '$streamId'});
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

  Future<List<Progress>> getSeriesProgress(String viewerId, int seriesId) async {
    final response = await _request('get_series_progress', params: {'viewer_id': viewerId, 'series_id': '$seriesId'});
    return _asList(response).map((item) => Progress.fromJson(_asMap(item), viewerId: viewerId)).toList(growable: false);
  }

  Future<List<Progress>> getRecentlyWatched(String viewerId, {ContentType? type, int limit = 20}) async {
    final response = await _request('get_recently_watched', params: {
      'viewer_id': viewerId,
      'limit': '$limit',
      if (type != null) 'type': type.wireName,
    });
    return _asList(response).map((item) => Progress.fromJson(_asMap(item), viewerId: viewerId)).toList(growable: false);
  }

  String getLiveStreamUrl(int streamId, {String format = 'm3u8'}) {
    final c = _requireCredentials();
    return '${c.server}/live/${c.username}/${c.password}/$streamId.$format';
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
    final categories = _asList(response).map((item) => Category.fromXtream(_asMap(item))).toList(growable: false);
    if (action == 'get_live_categories') {
      await _cache?.set('liveCategories', categories);
    }
    return categories;
  }

  Future<Object?> _request(String action, {Map<String, String> params = const {}, Map<String, String> body = const {}, String method = 'GET'}) {
    return _requestWithCredentials(_requireCredentials(), action, params: params, body: body, method: method);
  }

  Future<Object?> _requestWithCredentials(
    UserCredentials credentials,
    String? action, {
    Map<String, String> params = const {},
    Map<String, String> body = const {},
    Map<String, String> headers = const {},
    String method = 'GET',
  }) {
    final requestHeaders = <String, String>{'Accept': 'application/json', if (_isM3UEditor) _clientHeader: _clientValue, ...headers};
    return _transport(XtreamRequest(credentials: credentials, action: action, params: params, body: body, headers: requestHeaders, method: method));
  }

  UserCredentials _requireCredentials() {
    final credentials = _credentials;
    if (credentials == null) throw StateError('Xtream credentials not configured');
    return credentials;
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const <String, Object?>{};
}

List<Object?> _asList(Object? value) => value is List ? value.cast<Object?>() : const <Object?>[];

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
