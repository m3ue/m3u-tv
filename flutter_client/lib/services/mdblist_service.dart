// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/watch_history_service.dart';

// Register your own app at https://mdblist.com/developer/ with the type
// "Device Code App" and pass its id with MDBLIST_CLIENT_ID when building, or
// fall back to the app's own below. An MDBList client id is public, not a
// secret, and this flow uses no client secret.
const _kDefaultClientId = 'cATsHhss7WwiKfuocEVFrNZQgPuLJojA31UqC8rX';
const _envClientId = String.fromEnvironment('MDBLIST_CLIENT_ID');
const String _clientIdFromEnvironment = _envClientId == ''
    ? _kDefaultClientId
    : _envClientId;

const _kApi = 'https://api.mdblist.com';
const _kAppName = 'm3u-tv';
const _kKeyAccess = 'mdblist_access_token';
const _kKeyRefresh = 'mdblist_refresh_token';
const _kKeyExpiry = 'mdblist_token_expiry';
const _kKeyAccount = 'mdblist_account_name';

/// Access tokens last 30 days; used when a token response omits `expires_in`.
const int _kDefaultTokenLifetimeSeconds = 30 * 24 * 60 * 60;

enum MdblistAuthStatus { disconnected, pending, connected }

class MdblistPendingAuth {
  const MdblistPendingAuth({
    required this.userCode,
    required this.verificationUrl,
    required this.completeUrl,
    required this.deviceCode,
  });

  final String userCode;
  final String verificationUrl;

  /// [verificationUrl] with the code already filled in, for the QR code.
  final String completeUrl;
  final String deviceCode;
}

class MdblistRequest {
  const MdblistRequest({
    required this.path,
    this.form,
    this.json,
    this.accessToken,
  });

  final String path;
  final Map<String, String>? form;
  final Map<String, Object>? json;
  final String? accessToken;
}

class MdblistResponse {
  const MdblistResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;

  String? get error => switch (body['error']) {
    final String error => error,
    _ => null,
  };
}

typedef MdblistTransport =
    Future<MdblistResponse> Function(MdblistRequest request);

/// Looks up the signed-in account's display name for an access token.
typedef MdblistAccountNameLookup = Future<String?> Function(String accessToken);

/// Manages MDBList sign-in via the OAuth device flow, and scrobbling.
///
/// MDBList's scrobble endpoints follow Trakt's, except that an episode nests
/// its season and episode inside `show`. Every account shares one daily
/// request quota across all of its apps, so like Simkl it only gets events on
/// user actions, never a periodic heartbeat.
///
/// Call [init] once after construction to restore a persisted session.
/// [startDeviceAuth] publishes [pending] for the UI to show and polls until
/// [status] becomes [MdblistAuthStatus.connected].
class MdblistService extends ChangeNotifier implements WatchHistoryService {
  MdblistService({
    required SecureStorage storage,
    String clientId = _clientIdFromEnvironment,
    MdblistTransport? transport,
    Future<String?> Function()? appVersionResolver,
    MdblistAccountNameLookup? accountNameLookup,
  }) : _storage = storage,
       _accountNameLookup = accountNameLookup,
       _clientId = clientId,
       _transport = transport,
       _appVersionResolver =
           appVersionResolver ?? AppVersionService().currentVersion;

  final SecureStorage _storage;
  final String _clientId;
  final MdblistTransport? _transport;
  final Future<String?> Function() _appVersionResolver;
  final MdblistAccountNameLookup? _accountNameLookup;
  Future<String>? _appVersion;
  ApiClient? _apiInstance;
  ApiClient get _api => _apiInstance ??= ApiClient();

  MdblistAuthStatus _status = MdblistAuthStatus.disconnected;
  MdblistPendingAuth? _pending;
  Timer? _pollTimer;
  String? _accessToken;
  String? _accountName;
  Duration _pollInterval = Duration.zero;
  DateTime? _deviceCodeExpiresAt;
  final _scrobbleQueue = SerialQueue();
  var _authAttempt = 0;
  var _disposed = false;

  MdblistAuthStatus get status => _status;
  MdblistPendingAuth? get pending => _pending;

  /// The signed-in account's name, once known.
  String? get accountName => _accountName;

  bool get isConfigured => _clientId.isNotEmpty;

  @override
  bool get isConnected => _status == MdblistAuthStatus.connected;

  @override
  bool get wantsProgressHeartbeat => false;

  @visibleForTesting
  Duration get pollIntervalForTesting => _pollInterval;

  @visibleForTesting
  Future<void> pollForTesting() => _poll(_authAttempt);

  Future<void> init() async {
    final attempt = _authAttempt;
    final accessToken = await _storage.read(_kKeyAccess);
    if (_disposed || attempt != _authAttempt || accessToken == null) return;
    _accessToken = accessToken;
    _status = MdblistAuthStatus.connected;
    if (await _accessTokenExpired()) await _refresh();
    if (_disposed || attempt != _authAttempt) return;
    _accountName ??= await _storage.read(_kKeyAccount);
    if (_disposed || attempt != _authAttempt) return;
    notifyListeners();
    if (isConnected && _accountName == null) unawaited(_loadAccountName());
  }

  Future<void> startDeviceAuth() async {
    if (!isConfigured || _disposed) return;
    _clearPendingAttempt();
    final attempt = _authAttempt;
    _status = MdblistAuthStatus.pending;
    notifyListeners();
    try {
      final response = await _send(
        MdblistRequest(
          path: '/oauth/device-authorization/',
          form: {'client_id': _clientId, 'scope': 'write'},
        ),
      );
      if (_disposed || attempt != _authAttempt) return;
      if (response.statusCode >= 400) {
        cancelAuth();
        return;
      }
      final data = response.body;
      final verificationUrl =
          '${data['verification_uri'] ?? 'https://mdblist.com/oauth/device/'}';
      _pending = MdblistPendingAuth(
        userCode: '${data['user_code'] ?? ''}',
        verificationUrl: verificationUrl,
        completeUrl: '${data['verification_uri_complete'] ?? verificationUrl}',
        deviceCode: '${data['device_code'] ?? ''}',
      );
      _pollInterval = Duration(
        seconds: (data['interval'] as num?)?.toInt() ?? 5,
      );
      _deviceCodeExpiresAt = DateTime.now().add(
        Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 300),
      );
      notifyListeners();
      _schedulePoll(attempt);
    } on Object catch (_) {
      if (_disposed || attempt != _authAttempt) return;
      cancelAuth();
    }
  }

  void _schedulePoll(int attempt) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_disposed ||
        attempt != _authAttempt ||
        _status != MdblistAuthStatus.pending) {
      return;
    }
    final expiresAt = _deviceCodeExpiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      cancelAuth();
      return;
    }
    final delay = remaining < _pollInterval ? remaining : _pollInterval;
    _pollTimer = Timer(delay, () => unawaited(_poll(attempt)));
  }

  Future<void> _poll(int attempt) async {
    if (_disposed ||
        attempt != _authAttempt ||
        _status != MdblistAuthStatus.pending) {
      return;
    }
    final expiresAt = _deviceCodeExpiresAt;
    final code = _pending?.deviceCode;
    if (expiresAt == null ||
        !DateTime.now().isBefore(expiresAt) ||
        code == null) {
      cancelAuth();
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      final response = await _send(
        MdblistRequest(
          path: '/oauth/token/',
          form: {
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'client_id': _clientId,
            'device_code': code,
          },
        ),
      );
      if (_disposed || attempt != _authAttempt) return;
      if (response.statusCode < 400) {
        await _saveTokens(response.body);
        if (_disposed || attempt != _authAttempt) return;
        _clearPendingAttempt();
        _status = MdblistAuthStatus.connected;
        notifyListeners();
        unawaited(_loadAccountName());
        return;
      }
      switch (response.error) {
        case 'authorization_pending':
          _schedulePoll(attempt);
        case 'slow_down':
          _pollInterval += const Duration(seconds: 5);
          _schedulePoll(attempt);
        default:
          cancelAuth();
      }
    } on Object catch (_) {
      // A network blip shouldn't lose the code the user may be typing.
      if (!_disposed && attempt == _authAttempt) _schedulePoll(attempt);
    }
  }

  void cancelAuth() {
    _clearPendingAttempt();
    _status = MdblistAuthStatus.disconnected;
    if (!_disposed) notifyListeners();
  }

  Future<void> disconnect() async {
    _clearPendingAttempt();
    final token = _accessToken;
    _accessToken = null;
    await _clearStorage();
    _status = MdblistAuthStatus.disconnected;
    if (!_disposed) notifyListeners();
    if (token == null) return;
    try {
      await _send(
        MdblistRequest(
          path: '/oauth/revoke_token/',
          form: {'client_id': _clientId, 'token': token},
        ),
      );
    } on Object catch (_) {
      debugPrint('[MDBList] revoke failed');
    }
  }

  void _clearPendingAttempt() {
    _authAttempt += 1;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pending = null;
    _pollInterval = Duration.zero;
    _deviceCodeExpiresAt = null;
  }

  Future<bool> _accessTokenExpired() async {
    final expiry = int.tryParse(await _storage.read(_kKeyExpiry) ?? '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiry == null || expiry <= now + 60;
  }

  /// Exchanges the refresh token. Signs out only when MDBList rejects it: a
  /// network failure keeps the session and tries again on the next scrobble.
  Future<bool> _refresh() async {
    final attempt = _authAttempt;
    final refresh = await _storage.read(_kKeyRefresh);
    if (refresh == null || refresh.isEmpty) {
      await _signOutLocally(attempt);
      return false;
    }
    final MdblistResponse response;
    try {
      response = await _send(
        MdblistRequest(
          path: '/oauth/token/',
          form: {
            'grant_type': 'refresh_token',
            'client_id': _clientId,
            'refresh_token': refresh,
          },
        ),
      );
    } on Object catch (_) {
      return false;
    }
    if (_disposed || attempt != _authAttempt) return false;
    if (response.statusCode < 400) {
      await _saveTokens(response.body);
      return true;
    }
    if (response.statusCode == 400 || response.statusCode == 401) {
      await _signOutLocally(attempt);
    }
    return false;
  }

  Future<void> _signOutLocally(int attempt) async {
    if (_disposed || attempt != _authAttempt) return;
    _accessToken = null;
    await _clearStorage();
    _status = MdblistAuthStatus.disconnected;
    notifyListeners();
  }

  Future<void> _saveTokens(Map<String, Object?> data) async {
    final accessToken = '${data['access_token'] ?? ''}';
    if (accessToken.isEmpty) throw const FormatException('No access token');
    final expiresIn =
        (data['expires_in'] as num?)?.toInt() ?? _kDefaultTokenLifetimeSeconds;
    final expiry = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expiresIn;
    await _storage.write(_kKeyAccess, accessToken);
    final refreshToken = data['refresh_token'] as String?;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(_kKeyRefresh, refreshToken);
    }
    await _storage.write(_kKeyExpiry, '$expiry');
    _accessToken = accessToken;
  }

  Future<void> _clearStorage() async {
    _accountName = null;
    await _storage.delete(_kKeyAccess);
    await _storage.delete(_kKeyRefresh);
    await _storage.delete(_kKeyExpiry);
    await _storage.delete(_kKeyAccount);
  }

  /// Best effort: a failure leaves the name unknown until the next start.
  Future<void> _loadAccountName() async {
    final token = _accessToken;
    if (token == null) return;
    final lookup =
        _accountNameLookup ?? (_transport == null ? _fetchAccountName : null);
    if (lookup == null) return;
    try {
      final name = await lookup(token);
      if (_disposed || token != _accessToken || name == null || name.isEmpty) {
        return;
      }
      _accountName = name;
      await _storage.write(_kKeyAccount, name);
      if (!_disposed) notifyListeners();
    } on Object catch (_) {
      debugPrint('[MDBList] account lookup failed');
    }
  }

  Future<String?> _fetchAccountName(String accessToken) async {
    final version = await (_appVersion ??= _resolveAppVersion());
    final response = await _api.send(
      'GET',
      Uri.parse('$_kApi/user'),
      headers: {
        'user-agent': '$_kAppName/$version',
        'authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode >= 400 || response.bytes.isEmpty) return null;
    final body = await response.json();
    if (body is! Map<String, Object?>) return null;
    final name = body['username'] ?? body['name'];
    return name is String ? name : null;
  }

  /// The scrobble body: a `movie`, or a `show` with its season and episode
  /// nested inside, plus `progress`.
  @visibleForTesting
  static Map<String, Object> scrobbleBody({
    required String title,
    String? seriesTitle,
    int? season,
    int? episode,
    int? tmdbId,
    String? imdbId,
    int? year,
    required double progress,
  }) {
    final ids = <String, Object>{
      if ((tmdbId ?? 0) > 0) 'tmdb': tmdbId!,
      if (imdbId != null && imdbId.startsWith('tt')) 'imdb': imdbId,
    };
    final isEpisode = seriesTitle != null && season != null && episode != null;
    return <String, Object>{
      'progress': double.parse(progress.toStringAsFixed(2)),
      isEpisode ? 'show' : 'movie': <String, Object>{
        'title': isEpisode ? seriesTitle : title,
        'year': ?year,
        if (ids.isNotEmpty) 'ids': ids,
        if (isEpisode)
          'season': <String, Object>{
            'number': season,
            'episode': <String, Object>{'number': episode},
          },
      },
    };
  }

  /// Runs one at a time so events reach MDBList in order.
  @override
  Future<void> scrobble({
    required String action,
    required String title,
    String? seriesTitle,
    int? season,
    int? episode,
    int? tmdbId,
    String? imdbId,
    int? year,
    required double progress,
  }) {
    if (!isConnected) return Future<void>.value();
    final body = scrobbleBody(
      title: title,
      seriesTitle: seriesTitle,
      season: season,
      episode: episode,
      tmdbId: tmdbId,
      imdbId: imdbId,
      year: year,
      progress: progress,
    );
    return _scrobbleQueue.run(() async {
      try {
        await _sendScrobble(action, body);
      } on Object catch (_) {
        debugPrint('[MDBList] scrobble failed');
      }
    });
  }

  Future<void> _sendScrobble(String action, Map<String, Object> body) async {
    if (!isConnected) return;
    if (await _accessTokenExpired() && !await _refresh()) return;
    final response = await _postScrobble(action, body);
    if (response?.statusCode == 401) {
      if (!await _refresh()) return;
      await _postScrobble(action, body);
    }
  }

  Future<MdblistResponse?> _postScrobble(
    String action,
    Map<String, Object> body,
  ) async {
    final token = _accessToken;
    if (token == null) return null;
    return _send(
      MdblistRequest(
        path: '/scrobble/$action',
        json: body,
        accessToken: token,
      ),
    );
  }

  Future<String> _resolveAppVersion() async {
    try {
      final version = await _appVersionResolver();
      if (version != null && version.isNotEmpty) return version;
    } on Object catch (_) {
      debugPrint('[MDBList] app version unavailable');
    }
    return '1.0';
  }

  Future<MdblistResponse> _send(MdblistRequest request) async {
    final transport = _transport;
    if (transport != null) return transport(request);
    final version = await (_appVersion ??= _resolveAppVersion());
    final response = await _api.send(
      'POST',
      Uri.parse('$_kApi${request.path}'),
      form: request.form,
      json: request.json,
      headers: {
        'user-agent': '$_kAppName/$version',
        'authorization': ?(request.accessToken == null
            ? null
            : 'Bearer ${request.accessToken}'),
      },
    );
    if (response.bytes.isEmpty) {
      return MdblistResponse(response.statusCode, const <String, Object?>{});
    }
    final decoded = await response.json();
    return MdblistResponse(
      response.statusCode,
      decoded is Map<String, Object?> ? decoded : const <String, Object?>{},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _clearPendingAttempt();
    _apiInstance?.close();
    super.dispose();
  }
}
