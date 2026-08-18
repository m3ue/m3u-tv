// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_http_transport_stub.dart'
    if (dart.library.io) 'xtream_http_transport_io.dart';
import 'package:timezone/timezone.dart' as tz;

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
    this.bodyJson,
  });

  final int statusCode;
  final String method;
  final Uri uri;
  final String? reasonPhrase;
  final String? serverMessage;

  /// Parsed JSON body of the error response, when the server replied with a
  /// parseable body and `statusCode >= 400`. Null when the body was empty,
  /// non-JSON (e.g. an HTML error page), or when no body was parsed. Callers
  /// that need typed fields (e.g. `create_dvr_series_rule`'s 409 `rule_id`)
  /// should key off `statusCode` first and treat `bodyJson` as a best-effort
  /// enrichment — never trust its shape.
  final Object? bodyJson;

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

/// Thrown when the m3u-editor `schedule_dvr` endpoint reports a scheduling
/// failure (DVR disabled, channel not found, invalid window, etc.) or returns
/// a response shape that does not match the documented envelope.
///
/// Surfaced via `toString()` so the UI can render the server's message
/// directly through `appRecordingFailed(error.toString())`.
class XtreamDvrScheduleException implements Exception {
  const XtreamDvrScheduleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by `XtreamService.createDvrSeriesRule` when the server rejects a
/// `create_dvr_series_rule` call because a series rule for the same
/// normalized title already exists on this playlist/DVR setting (the A3
/// duplicate guard — HTTP 409). Carries the existing rule's id when the
/// server returned one, so the caller can flip straight to the "rule exists"
/// state instead of asking the user to confirm another create.
class DvrSeriesRuleExistsException implements Exception {
  const DvrSeriesRuleExistsException(this.message, {this.ruleId});

  final String message;
  final int? ruleId;

  @override
  String toString() => message;
}

/// Outcome of `XtreamService.createDvrSeriesRule`, surfaced by the AppShell
/// wrapper that owns the refresh-rules-on-mutation pattern. The UI layers
/// (`ShowDetailScreen`, `LiveTvScreen`) branch on this rather than the raw
/// exception so duplicate vs failed stays distinguishable all the way to the
/// SnackBar.
enum CreateDvrSeriesRuleOutcome {
  /// Rule was created on the server.
  created,

  /// Server rejected the create as a duplicate of an existing rule
  /// (HTTP 409). The local rules cache has been refreshed so the UI can
  /// show the existing-rule state.
  duplicate,

  /// Create failed for any other reason (network, auth, unknown 4xx/5xx).
  failed,
}

/// Thrown when an m3u-editor `request_*` action returns its documented error
/// envelope (`{ error: { code, message } }`) or a response shape that doesn't
/// match the expected envelope. [code] is one of the values advertised in
/// `m3u_editor.requests.error_codes` (e.g. `already_requested`,
/// `providers_unavailable`, `rate_limited`), letting callers branch on it
/// without string-matching [message].
class XtreamRequestException implements Exception {
  const XtreamRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
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
  final Map<String, Object?> body;
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

class AIOStreamsCatalog {
  const AIOStreamsCatalog({
    required this.id,
    required this.type,
    required this.name,
    this.searchable = false,
  });

  factory AIOStreamsCatalog.fromJson(Map<String, dynamic> json) =>
      AIOStreamsCatalog(
        id: '${json['id'] ?? ''}',
        type: '${json['type'] ?? ''}',
        name: '${json['name'] ?? ''}',
        searchable: json['searchable'] == true,
      );

  final String id;
  final String type;
  final String name;
  final bool searchable;
}

class AIOStreamsIntegration {
  const AIOStreamsIntegration({
    required this.id,
    required this.name,
    required this.catalogs,
    this.logoUrl,
  });

  factory AIOStreamsIntegration.fromJson(Map<String, dynamic> json) =>
      AIOStreamsIntegration(
        id: _asInt(json['id']),
        name: '${json['name'] ?? ''}',
        logoUrl: json['logo'] as String?,
        catalogs: _asList(json['catalogs'])
            .whereType<Map<String, dynamic>>()
            .map(AIOStreamsCatalog.fromJson)
            .toList(growable: false),
      );

  final int id;
  final String name;
  final String? logoUrl;
  final List<AIOStreamsCatalog> catalogs;
}

class ProxyStreamProfile {
  const ProxyStreamProfile({
    required this.id,
    required this.name,
    this.description,
    this.format,
  });

  factory ProxyStreamProfile.fromJson(Map<String, dynamic> json) =>
      ProxyStreamProfile(
        id: _asInt(json['id']),
        name: '${json['name'] ?? ''}',
        description: json['description'] as String?,
        format: json['format'] as String?,
      );

  final int id;
  final String name;
  final String? description;
  final String? format;
}

/// Proxy playback capability advertised by the backend.
///
/// [forced] means the playlist already routes every stream through the proxy,
/// so the proxy cannot be turned off client-side — profile selection still
/// applies. [profiles] is the set of transcoding profiles this user may apply.
class ProxyCapability {
  const ProxyCapability({
    required this.forced,
    this.profiles = const <ProxyStreamProfile>[],
  });

  factory ProxyCapability.fromJson(Map<String, dynamic> json) =>
      ProxyCapability(
        forced: json['forced'] == true,
        profiles: _asList(json['profiles'])
            .whereType<Map<String, dynamic>>()
            .map(ProxyStreamProfile.fromJson)
            .toList(growable: false),
      );

  final bool forced;
  final List<ProxyStreamProfile> profiles;
}

/// Content request capability advertised by the backend when guest content
/// requests (Sonarr/Radarr via ArrIntegration) are enabled for this playlist
/// auth. [contentTypes] is which of `movie`/`series` have an enabled,
/// guest-enabled integration behind them; [autoApproval] mirrors whether this
/// guest's requests are sent to Arr immediately or held for admin approval.
class RequestsCapability {
  const RequestsCapability({
    this.contentTypes = const <String>[],
    this.autoApproval = false,
  });

  factory RequestsCapability.fromJson(Map<String, dynamic> json) =>
      RequestsCapability(
        contentTypes: _asList(
          json['content_types'],
        ).map((type) => '$type').toList(growable: false),
        autoApproval: '${json['approval_behavior'] ?? ''}' == 'auto_approval',
      );

  final List<String> contentTypes;
  final bool autoApproval;

  bool supports(String type) => contentTypes.contains(type);
}

class XtreamAuthResponse {
  const XtreamAuthResponse({
    required this.isAuthenticated,
    this.status,
    this.m3uEditorVersion,
    this.features = const <String>[],
    this.aiostreamsIntegrations = const <AIOStreamsIntegration>[],
    this.proxy,
    this.requests,
  });

  final bool isAuthenticated;
  final String? status;
  final String? m3uEditorVersion;
  final List<String> features;
  final List<AIOStreamsIntegration> aiostreamsIntegrations;
  final ProxyCapability? proxy;
  final RequestsCapability? requests;

  bool hasFeature(String feature) => features.contains(feature);
  bool get hasAioStreams =>
      hasFeature('aiostreams') && aiostreamsIntegrations.isNotEmpty;
  bool get hasProxy => hasFeature('proxy') && proxy != null;
  bool get hasRequests => hasFeature('requests') && requests != null;
}

class XtreamSessionSnapshot {
  const XtreamSessionSnapshot._({
    required UserCredentials? credentials,
    required tz.Location serverLocation,
    required bool isM3UEditor,
  }) : _credentials = credentials,
       _serverLocation = serverLocation,
       _isM3UEditor = isM3UEditor;

  final UserCredentials? _credentials;
  final tz.Location _serverLocation;
  final bool _isM3UEditor;
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
  tz.Location _serverLocation = tz.UTC;
  bool _isM3UEditor = false;
  final Generation _sessionGeneration = Generation();
  final Generation _authenticationGeneration = Generation();
  int _liveCategoryCacheSuppressions = 0;

  bool get isConfigured => _credentials != null;

  /// The IANA timezone name resolved from the server's `server_info.timezone`
  /// field during the last successful [authenticate] call.
  String get serverTimezone => _serverLocation.name;

  UserCredentials? get credentials => _credentials;

  XtreamSessionSnapshot snapshotSession() => XtreamSessionSnapshot._(
    credentials: _credentials,
    serverLocation: _serverLocation,
    isM3UEditor: _isM3UEditor,
  );

  void restoreSession(XtreamSessionSnapshot snapshot) {
    _credentials = snapshot._credentials;
    _serverLocation = snapshot._serverLocation;
    _isM3UEditor = snapshot._isM3UEditor;
    _sessionGeneration.advance();
    _authenticationGeneration.advance();
  }

  Future<XtreamAuthResponse> authenticate(UserCredentials credentials) async {
    final authenticationGeneration = _authenticationGeneration.advance();
    _sessionGeneration.advance();
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

    final tzName =
        _stringOrNull(_asMap(json['server_info'])['timezone']) ?? 'UTC';
    late final tz.Location serverLocation;
    try {
      serverLocation = tz.getLocation(tzName);
    } on Exception catch (_) {
      serverLocation = tz.UTC;
    }
    final features = _asList(m3uEditor['features'])
        .map((feature) => '$feature')
        .where((feature) => feature.isNotEmpty)
        .toList(growable: false);
    final aiostreamsIntegrations = _asList(m3uEditor['aiostreams'])
        .whereType<Map<String, dynamic>>()
        .map(AIOStreamsIntegration.fromJson)
        .toList(growable: false);
    final proxyJson = m3uEditor['proxy'];
    final proxy = proxyJson is Map<String, dynamic>
        ? ProxyCapability.fromJson(proxyJson)
        : null;
    final requestsJson = m3uEditor['requests'];
    final requests = requestsJson is Map<String, dynamic>
        ? RequestsCapability.fromJson(requestsJson)
        : null;
    final authResponse = XtreamAuthResponse(
      isAuthenticated: true,
      status: status,
      m3uEditorVersion: '${m3uEditor['version'] ?? ''}',
      features: features,
      aiostreamsIntegrations: aiostreamsIntegrations,
      proxy: proxy,
      requests: requests,
    );
    if (!_authenticationGeneration.isStale(authenticationGeneration)) {
      _credentials = normalized;
      _isM3UEditor = true;
      _serverLocation = serverLocation;
    }
    return authResponse;
  }

  void clearCredentials() {
    _credentials = null;
    _isM3UEditor = false;
    _serverLocation = tz.UTC;
    _sessionGeneration.advance();
    _authenticationGeneration.advance();
  }

  Future<List<Category>> getLiveCategories() async =>
      _categories('get_live_categories');
  Future<List<Category>> getLiveCategoriesUncached() async {
    _liveCategoryCacheSuppressions += 1;
    try {
      return await getLiveCategories();
    } finally {
      _liveCategoryCacheSuppressions -= 1;
    }
  }

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

  Future<List<DvrRecording>> getDvrRecordings({
    DvrRecordingStatus? status,
    int? limit,
  }) async {
    final params = {'status': ?status?.name, 'limit': ?limit?.toString()};
    final response = await _request('get_dvr_recordings', params: params);
    return _asList(response)
        .map((item) => DvrRecording.fromXtream(_asMap(item)))
        .toList(growable: false);
  }

  Future<List<DvrRecording>> getDvrRecordingsFor(
    UserCredentials credentials, {
    DvrRecordingStatus? status,
    int? limit,
  }) async {
    final response = await _requestWithCredentials(
      credentials,
      'get_dvr_recordings',
      params: {'status': ?status?.name, 'limit': ?limit?.toString()},
    );
    return _asList(response)
        .map((item) => DvrRecording.fromXtream(_asMap(item)))
        .toList(growable: false);
  }

  Future<DvrRecording> getDvrRecording(String uuid) async {
    // m3u-editor's XtreamApiController::getDvrRecording() reads
    // `recording_id`, not `uuid`.
    final params = {'recording_id': uuid};
    final response = await _request('get_dvr_recording', params: params);
    return DvrRecording.fromXtream(_asMap(response));
  }

  Future<DvrRecording> getDvrRecordingFor(
    UserCredentials credentials,
    String uuid,
  ) async {
    final response = await _requestWithCredentials(
      credentials,
      'get_dvr_recording',
      params: {'recording_id': uuid},
    );
    return DvrRecording.fromXtream(_asMap(response));
  }

  /// Fetches DVR storage usage against quota via m3u-editor's
  /// `get_dvr_storage` action. Older servers without this action will
  /// return an error response, which callers should treat as "unsupported"
  /// and hide the feature rather than surfacing an error.
  Future<DvrStorageInfo> getDvrStorage() async {
    final response = await _request('get_dvr_storage');
    return DvrStorageInfo.fromXtream(_asMap(response));
  }

  Future<DvrStorageInfo> getDvrStorageFor(
    UserCredentials credentials,
  ) async {
    final response = await _requestWithCredentials(
      credentials,
      'get_dvr_storage',
    );
    return DvrStorageInfo.fromXtream(_asMap(response));
  }

  /// Schedules a one-shot DVR recording on m3u-editor's `schedule_dvr` action.
  ///
  /// The m3u-editor endpoint responds with an envelope:
  /// - Success: `{ success: true, rule_id: int, message: string }`
  /// - Failure: `{ error: string }` with HTTP 4xx
  ///
  /// Returns the created rule's id on success. Throws [XtreamDvrScheduleException]
  /// on failure so callers can surface the server's error message to the user
  /// instead of silently treating the failure as a successful schedule.
  Future<int> scheduleDvr({
    required int channelId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) => scheduleDvrFor(
    _requireCredentials(),
    channelId: channelId,
    title: title,
    startTime: startTime,
    endTime: endTime,
  );

  Future<int> scheduleDvrFor(
    UserCredentials credentials, {
    required int channelId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final response = await _requestWithCredentials(
      credentials,
      'schedule_dvr',
      method: 'POST',
      body: {
        'channel_id': '$channelId',
        'title': title,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
      },
    );
    final map = _asMap(response);
    final errorMessage = map['error'];
    if (errorMessage != null && '$errorMessage'.trim().isNotEmpty) {
      throw XtreamDvrScheduleException('$errorMessage');
    }
    final ruleId = int.tryParse('${map['rule_id'] ?? ''}');
    if (ruleId != null && ruleId > 0) {
      return ruleId;
    }
    throw const XtreamDvrScheduleException(
      'm3u-editor returned an unexpected response for schedule_dvr.',
    );
  }

  /// Cancels a scheduled or in-progress DVR recording on
  /// m3u-editor's `cancel_dvr_recording` action.
  ///
  /// Valid for statuses `scheduled` and `recording`. Server returns
  /// `{ success: true }` on success or HTTP 404 with `{ error }` if the
  /// recording is not found or no longer cancellable. Throws the standard
  /// request exception on failure so callers can surface the error message.
  Future<void> cancelDvrRecording(String uuid) =>
      cancelDvrRecordingFor(_requireCredentials(), uuid);

  Future<void> cancelDvrRecordingFor(
    UserCredentials credentials,
    String uuid,
  ) async {
    final response = await _requestWithCredentials(
      credentials,
      'cancel_dvr_recording',
      method: 'POST',
      body: {'recording_id': uuid},
    );
    final map = _asMap(response);
    final errorMessage = map['error'];
    if (errorMessage != null && '$errorMessage'.trim().isNotEmpty) {
      throw XtreamDvrScheduleException('$errorMessage');
    }
  }

  /// Deletes a completed/failed/cancelled DVR recording on
  /// m3u-editor's `delete_dvr_recording` action.
  ///
  /// Server returns `{ success: true }` on success or HTTP 404 with
  /// `{ error }` if the recording is not found or not in a deletable
  /// state. Throws the standard request exception on failure.
  Future<void> deleteDvrRecording(String uuid) =>
      deleteDvrRecordingFor(_requireCredentials(), uuid);

  Future<void> deleteDvrRecordingFor(
    UserCredentials credentials,
    String uuid,
  ) async {
    final response = await _requestWithCredentials(
      credentials,
      'delete_dvr_recording',
      method: 'POST',
      body: {'recording_id': uuid},
    );
    final map = _asMap(response);
    final errorMessage = map['error'];
    if (errorMessage != null && '$errorMessage'.trim().isNotEmpty) {
      throw XtreamDvrScheduleException('$errorMessage');
    }
  }

  /// Searches every guest-enabled Arr integration for [query] via
  /// `request_search`. [type] restricts to `movie` or `series`; omit to
  /// search both. Throws [XtreamRequestException] on the documented error
  /// envelope (e.g. `providers_unavailable` when every provider failed).
  Future<List<ContentRequestSearchResult>> searchContentRequests(
    String query, {
    String? type,
    int page = 1,
    int perPage = 20,
  }) => searchContentRequestsFor(
    _requireCredentials(),
    query,
    type: type,
    page: page,
    perPage: perPage,
  );

  Future<List<ContentRequestSearchResult>> searchContentRequestsFor(
    UserCredentials credentials,
    String query, {
    String? type,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _requestWithCredentials(
      credentials,
      'request_search',
      params: {
        'query': query,
        'type': ?type,
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    final data = _asMap(_unwrapRequestEnvelope(response)['data']);
    return _asList(data['results'])
        .map((item) => ContentRequestSearchResult.fromJson(_asMap(item)))
        .toList(growable: false);
  }

  /// Submits a content request via `request_submit`. Requests the whole
  /// series for `type: 'series'` — m3u-editor monitors every season when no
  /// `seasons` selection is sent, so there's no per-season picker to wire up.
  ///
  /// Returns the created [MediaRequestSummary], whose `status` is either
  /// `pendingApproval` or `approved` depending on the guest's
  /// `auto_approve_requests` setting. Throws [XtreamRequestException] on
  /// failure (e.g. `already_requested`, `already_available`).
  Future<MediaRequestSummary> submitContentRequest({
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
  }) => submitContentRequestFor(
    _requireCredentials(),
    type: type,
    integrationId: integrationId,
    externalId: externalId,
    seasons: seasons,
  );

  Future<MediaRequestSummary> submitContentRequestFor(
    UserCredentials credentials, {
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
  }) async {
    final response = await _requestWithCredentials(
      credentials,
      'request_submit',
      method: 'POST',
      body: {
        'type': type,
        'integration_id': '$integrationId',
        'external_id': externalId,
        'seasons': ?seasons,
      },
    );
    final data = _asMap(_unwrapRequestEnvelope(response)['data']);
    return MediaRequestSummary.fromJson(_asMap(data['request']));
  }

  /// The requesting guest's own request history via `request_history`.
  Future<List<MediaRequestSummary>> getMediaRequests({
    int page = 1,
    int perPage = 50,
  }) async {
    final response = await _request(
      'request_history',
      params: {'page': '$page', 'per_page': '$perPage'},
    );
    final data = _asMap(_unwrapRequestEnvelope(response)['data']);
    return _asList(data['requests'])
        .map((item) => MediaRequestSummary.fromJson(_asMap(item)))
        .toList(growable: false);
  }

  /// Refreshes a single request's status via `request_status`, including
  /// live download progress once approved.
  Future<MediaRequestSummary> getMediaRequestStatus(int requestId) async {
    final response = await _request(
      'request_status',
      params: {'request_id': '$requestId'},
    );
    final data = _asMap(_unwrapRequestEnvelope(response)['data']);
    return MediaRequestSummary.fromJson(_asMap(data['request']));
  }

  /// Dismisses a completed or rejected request via `request_dismiss`.
  Future<void> dismissMediaRequest(int requestId) async {
    final response = await _request(
      'request_dismiss',
      method: 'POST',
      body: {'request_id': '$requestId'},
    );
    _unwrapRequestEnvelope(response);
  }

  /// Unwraps the shared `request_*` action envelope
  /// (`{ api_version, data, meta? }` / `{ api_version, error: { code, message } }`),
  /// throwing [XtreamRequestException] on the error shape.
  Map<String, Object?> _unwrapRequestEnvelope(Object? response) {
    final envelope = _asMap(response);
    final error = envelope['error'];
    if (error != null) {
      final errorMap = _asMap(error);
      throw XtreamRequestException(
        '${errorMap['code'] ?? 'unknown'}',
        '${errorMap['message'] ?? 'The request could not be completed.'}',
      );
    }
    return envelope;
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
              edlUrl: episode.edlUrl,
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

  Future<Viewer> createViewer(String name) =>
      createViewerFor(_requireCredentials(), name);

  Future<Viewer> createViewerFor(
    UserCredentials credentials,
    String name,
  ) async => Viewer.fromJson(
    _asMap(
      await _requestWithCredentials(
        credentials,
        'create_viewer',
        method: 'POST',
        body: {'name': name},
      ),
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

  /// Server-authoritative favorites for a viewer. Each entry is a raw map with
  /// `content_type`, `stream_id`, `aio_item_id`, `imdb_id`, `tmdb_id`, and (for
  /// aiostreams entries) `title`, `thumbnail_url`, `item_type`,
  /// `aio_integration_id`, `favorited_at`.
  ///
  /// Pass [imdbId] instead of/alongside [contentType] to cross-reference: find
  /// every favorite of a title regardless of which content_type or source it
  /// was favorited under (e.g. an AIOStreams favorite showing up as "already
  /// favorited" on the equivalent Xtream VOD entry).
  Future<List<Map<String, Object?>>> getFavorites(
    String viewerId, {
    String? contentType,
    String? imdbId,
  }) async {
    final response = await _request(
      'get_favorites',
      params: {
        'viewer_id': viewerId,
        'content_type': ?contentType,
        'imdb_id': ?imdbId,
      },
    );
    return _asList(response).map(_asMap).toList(growable: false);
  }

  /// [imdbId]/[tmdbId] are only honored by the server for `aiostreams`
  /// favorites (addon content the server can't independently verify) — for
  /// `vod`/`series` the server always resolves cross-reference ids itself
  /// from the local Channel/Series row, ignoring any value passed here.
  Future<void> toggleFavorite({
    required String viewerId,
    required String contentType,
    int? streamId,
    String? aioItemId,
    required bool favorited,
    String? imdbId,
    String? tmdbId,
    String? title,
    String? thumbnailUrl,
    String? itemType,
    int? aioIntegrationId,
  }) async {
    await _request(
      'toggle_favorite',
      method: 'POST',
      body: {
        'viewer_id': viewerId,
        'content_type': contentType,
        'stream_id': ?streamId?.toString(),
        'aio_item_id': ?aioItemId,
        'favorited': '$favorited',
        'imdb_id': ?imdbId,
        'tmdb_id': ?tmdbId,
        'title': ?title,
        'thumbnail_url': ?thumbnailUrl,
        'item_type': ?itemType,
        'aio_integration_id': ?aioIntegrationId?.toString(),
      },
    );
  }

  /// One-time reconciliation of pre-existing local-only favorites into the
  /// account. Returns the merged, now-authoritative server set. Server only
  /// ever adds — never deletes — so this is safe to call speculatively.
  Future<List<Map<String, Object?>>> syncFavorites(
    String viewerId,
    List<Map<String, Object?>> favorites,
  ) async {
    final response = await _request(
      'sync_favorites',
      method: 'POST',
      body: {'viewer_id': viewerId, 'favorites': favorites},
    );
    return _asList(response).map(_asMap).toList(growable: false);
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
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (channels.isEmpty) return const <EpgProgram>[];
    final dates = <DateTime?>[null];
    if (startDate != null) {
      final firstDate = DateTime.utc(
        startDate.year,
        startDate.month,
        startDate.day,
      );
      final lastDate = endDate == null
          ? firstDate
          : DateTime.utc(endDate.year, endDate.month, endDate.day);
      if (lastDate.isBefore(firstDate)) {
        throw ArgumentError.value(
          endDate,
          'endDate',
          'Must not precede startDate',
        );
      }
      dates
        ..clear()
        ..addAll([
          for (
            var date = firstDate;
            !date.isAfter(lastDate);
            date = date.add(const Duration(days: 1))
          )
            date,
        ]);
    }
    final programs = <EpgProgram>[];
    for (var start = 0; start < channels.length; start += _epgBatchSize) {
      final chunk = channels
          .skip(start)
          .take(_epgBatchSize)
          .toList(growable: false);
      final channelIdsByStream = <String, String>{
        for (final channel in chunk)
          '${channel.id}':
              channel.epgChannelId ?? channel.tvgName ?? channel.name,
      };
      for (final date in dates) {
        final response = await _request(
          'get_epg_batch',
          params: {
            'stream_ids': chunk.map((channel) => '${channel.id}').join(','),
            'limit': '$limit',
            if (date != null) 'date': _formatEpgDate(date),
          },
        );
        programs.addAll(
          _parseEpgPrograms(response, channelIdsByStream: channelIdsByStream),
        );
      }
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
    final normalizedStart = tz.TZDateTime.from(start, _serverLocation);
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

  /// Creates a persistent series recording rule on m3u-editor's
  /// `create_dvr_series_rule` action.
  ///
  /// Returns the new rule's integer id, or `0` if the response did not include
  /// one (treat as failure — callers should fall back to refreshing the rule
  /// list before deciding whether the create succeeded).
  ///
  /// All optional parameters follow **omit-to-inherit**: when a value is
  /// null the corresponding query key is dropped entirely so the server can
  /// fall back to `dvr_setting.default_*` instead of overriding the user's
  /// DVR settings with a guessed default.
  ///
  /// Throws [DvrSeriesRuleExistsException] (carrying the existing rule id
  /// when the server included it) on the A3 duplicate-guard 409. Throws
  /// any other [XtreamHttpException] unchanged.
  Future<int> createDvrSeriesRule({
    int? channelId,
    required String title,
    DvrMatchMode? matchMode,
    DvrSeriesMode? seriesMode,
    int? keepLast,
    int? priority,
    int? startEarlySeconds,
    int? endLateSeconds,
  }) async {
    final params = <String, String>{
      'title': title,
      if (channelId != null) 'channel_id': '$channelId',
      if (matchMode != null) 'match_mode': matchMode.wireValue,
      if (seriesMode != null) 'series_mode': seriesMode.wireValue,
      if (keepLast != null) 'keep_last': '$keepLast',
      if (priority != null) 'priority': '$priority',
      if (startEarlySeconds != null)
        'start_early_seconds': '$startEarlySeconds',
      if (endLateSeconds != null) 'end_late_seconds': '$endLateSeconds',
    };
    try {
      final response = await _request(
        'create_dvr_series_rule',
        params: params,
      );
      final map = _asMap(response);
      final id = map['rule_id'];
      if (id is num) return id.toInt();
      if (id is String) return int.tryParse(id) ?? 0;
      return 0;
    } on XtreamHttpException catch (error) {
      if (error.statusCode != 409) rethrow;
      final body = error.bodyJson;
      final ruleId =
          body is Map &&
              body['rule_id'] is num &&
              (body['duplicate'] == true || body['rule_id'] != null)
          ? (body['rule_id'] as num).toInt()
          : null;
      throw DvrSeriesRuleExistsException(
        error.serverMessage ?? 'Series rule already exists',
        ruleId: ruleId,
      );
    }
  }

  /// Lists every active series recording rule for the current playlist via
  /// m3u-editor's `list_dvr_series_rules` action.
  Future<List<DvrSeriesRule>> listDvrSeriesRules() async =>
      listDvrSeriesRulesFor(_requireCredentials());

  Future<List<DvrSeriesRule>> listDvrSeriesRulesFor(
    UserCredentials credentials,
  ) async {
    final response = await _requestWithCredentials(
      credentials,
      'list_dvr_series_rules',
    );
    return _asList(response)
        .map((item) => DvrSeriesRule.fromXtream(_asMap(item)))
        .toList(growable: false);
  }

  /// Deletes a series recording rule by integer id via m3u-editor's
  /// `delete_dvr_series_rule` action.
  Future<void> deleteDvrSeriesRule(int id) async {
    await _request(
      'delete_dvr_series_rule',
      params: {'rule_id': '$id'},
    );
  }

  /// Updates an existing series recording rule via m3u-editor's
  /// `update_dvr_series_rule` action.
  ///
  /// Omit-to-inherit ON UPDATE differs from create: absent fields keep their
  /// current value (they are never nulled out). Only fields the caller passes
  /// here are sent. [channelId] is special — null means "any channel", so it is
  /// always sent (as an empty value) to distinguish an explicit switch to
  /// any-channel from "leave unchanged".
  Future<void> updateDvrSeriesRule({
    required int ruleId,
    int? channelId,
    DvrMatchMode? matchMode,
    DvrSeriesMode? seriesMode,
    int? keepLast,
    int? priority,
    int? startEarlySeconds,
    int? endLateSeconds,
  }) async {
    final params = <String, String>{
      'rule_id': '$ruleId',
      if (channelId == null) 'channel_id': '' else 'channel_id': '$channelId',
      if (matchMode != null) 'match_mode': matchMode.wireValue,
      if (seriesMode != null) 'series_mode': seriesMode.wireValue,
      if (keepLast != null) 'keep_last': '$keepLast',
      if (priority != null) 'priority': '$priority',
      if (startEarlySeconds != null)
        'start_early_seconds': '$startEarlySeconds',
      if (endLateSeconds != null) 'end_late_seconds': '$endLateSeconds',
    };
    await _request(
      'update_dvr_series_rule',
      params: params,
    );
  }

  /// Searches EPG shows across the playlist's mapped channels via
  /// m3u-editor's `search_epg_shows` action. Returns shows grouped by
  /// normalized title, sorted by next-airing-first. Queries shorter than
  /// two characters short-circuit to an empty list rather than hitting the
  /// server.
  Future<List<EpgShow>> searchEpgShows(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const <EpgShow>[];
    final response = await _request(
      'search_epg_shows',
      params: {'q': trimmed},
    );
    return _asList(
      response,
    ).map((item) => EpgShow.fromXtream(_asMap(item))).toList(growable: false);
  }

  Future<List<Category>> _categories(String action) async {
    final sessionGeneration = _sessionGeneration.current;
    final response = await _request(action);
    final categories = _asList(
      response,
    ).map((item) => Category.fromXtream(_asMap(item))).toList(growable: false);
    if (_liveCategoryCacheSuppressions == 0 &&
        action == 'get_live_categories' &&
        !_sessionGeneration.isStale(sessionGeneration)) {
      await _cache?.set('liveCategories', categories);
    }
    return categories;
  }

  Future<Object?> _request(
    String action, {
    Map<String, String> params = const {},
    Map<String, Object?> body = const {},
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
    Map<String, Object?> body = const {},
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
    subtitle: _decodedSubtitle(json['subtitle']),
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

final _base64LikeText = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

/// True if [text] contains a control character other than tab/LF/CR. Real
/// programme text never contains these, but short all-letter plain-text
/// values (e.g. a one-word episode subtitle like "GAME") can coincidentally
/// satisfy the base64 shape check and "decode" into byte garbage, so this
/// gate rejects that outcome and falls back to the original plain text.
bool _hasControlCharacters(String text) => text.codeUnits.any(
  (unit) => unit < 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D,
);

String _decodeBase64WhenApplicable(String value) {
  if (value.isEmpty) return value;
  final text = value.trim();
  if (text.length % 4 != 0 || !_base64LikeText.hasMatch(text)) {
    return value;
  }
  try {
    final normalized = base64.normalize(text);
    final decoded = utf8.decode(
      base64.decode(normalized),
      allowMalformed: false,
    );
    if (decoded.isEmpty || _hasControlCharacters(decoded)) return value;
    return decoded;
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

String _formatEpgDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${twoDigits(value.month)}-${twoDigits(value.day)}';
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text.isEmpty ? null : text;
}

String? _decodedSubtitle(Object? value) {
  final raw = _stringOrNull(value);
  return raw == null ? null : nullIfBlank(_decodeBase64WhenApplicable(raw));
}
