// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/pkce.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/watch_history_service.dart';

// Register your own app at https://simkl.com/settings/developer/ with the client
// type "TV, devices & command line" and pass its id with SIMKL_CLIENT_ID when
// building, or fall back to the app's own below. A Simkl client id is public,
// not a secret, and this flow uses no client secret.
const _kDefaultClientId =
    'a3a6b6b8105c1df0ebce03f1c52665c4b664e7fc0368d3b4c81c94ef842f4f13';
const _envClientId = String.fromEnvironment('SIMKL_CLIENT_ID');
const String _clientIdFromEnvironment = _envClientId == ''
    ? _kDefaultClientId
    : _envClientId;

const _kApi = 'https://api.simkl.com';
const _kAppName = 'm3u-tv';
const _kScope = 'media:read media:write';
const _kKeyAccess = 'simkl_access_token';
const _kKeyRefresh = 'simkl_refresh_token';
const _kKeyExpiry = 'simkl_token_expiry';
const _kKeyAccount = 'simkl_account_name';

/// Access tokens last 7 days; used when a token response omits `expires_in`.
const int _kDefaultTokenLifetimeSeconds = 7 * 24 * 60 * 60;

enum SimklAuthStatus { disconnected, pending, connected }

class SimklPendingAuth {
  const SimklPendingAuth({
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

class SimklRequest {
  const SimklRequest({
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

class SimklResponse {
  const SimklResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;

  String? get error => body['error'] as String?;
}

typedef SimklTransport = Future<SimklResponse> Function(SimklRequest request);

/// Looks up the signed-in account's display name for an access token.
typedef SimklAccountNameLookup = Future<String?> Function(String accessToken);

/// Manages Simkl sign-in via the OAuth device flow, and scrobbling.
///
/// Call [init] once after construction to restore a persisted session.
/// [startDeviceAuth] publishes [pending] for the UI to show and polls until
/// [status] becomes [SimklAuthStatus.connected].
class SimklService extends ChangeNotifier implements WatchHistoryService {
  SimklService({
    required SecureStorage storage,
    String clientId = _clientIdFromEnvironment,
    SimklTransport? transport,
    String Function()? codeVerifierFactory,
    Duration writeLockRetryDelay = const Duration(seconds: 21),
    Future<String?> Function()? appVersionResolver,
    SimklAccountNameLookup? accountNameLookup,
  }) : _storage = storage,
       _accountNameLookup = accountNameLookup,
       _clientId = clientId,
       _transport = transport,
       _codeVerifierFactory = codeVerifierFactory ?? generatePkceVerifier,
       _writeLockRetryDelay = writeLockRetryDelay,
       _appVersionResolver =
           appVersionResolver ?? AppVersionService().currentVersion;

  final SecureStorage _storage;
  final String _clientId;
  final SimklTransport? _transport;
  final String Function() _codeVerifierFactory;
  final Duration _writeLockRetryDelay;
  final Future<String?> Function() _appVersionResolver;
  final SimklAccountNameLookup? _accountNameLookup;
  Future<String>? _appVersion;
  ApiClient? _apiInstance;
  ApiClient get _api => _apiInstance ??= ApiClient();

  SimklAuthStatus _status = SimklAuthStatus.disconnected;
  SimklPendingAuth? _pending;
  Timer? _pollTimer;
  String? _accessToken;
  String? _accountName;
  String? _codeVerifier;
  Duration _pollInterval = Duration.zero;
  DateTime? _deviceCodeExpiresAt;
  final _scrobbleQueue = SerialQueue();
  var _authAttempt = 0;
  var _disposed = false;

  SimklAuthStatus get status => _status;
  SimklPendingAuth? get pending => _pending;

  /// The signed-in account's name, once known. Sign-ins from before it was
  /// stored look it up on the next start, so no reconnect is needed.
  String? get accountName => _accountName;

  bool get isConfigured => _clientId.isNotEmpty;

  @override
  bool get isConnected => _status == SimklAuthStatus.connected;

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
    _status = SimklAuthStatus.connected;
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
    final verifier = _codeVerifierFactory();
    _codeVerifier = verifier;
    _status = SimklAuthStatus.pending;
    notifyListeners();
    try {
      // The docs disagree on whether the device flow needs PKCE, so send it:
      // an authorization server ignores it where it isn't required.
      final response = await _send(
        SimklRequest(
          path: '/oauth2/device',
          form: {
            'client_id': _clientId,
            'scope': _kScope,
            'code_challenge': pkceChallenge(verifier),
            'code_challenge_method': 'S256',
          },
        ),
      );
      if (_disposed || attempt != _authAttempt) return;
      if (response.statusCode >= 400) {
        cancelAuth();
        return;
      }
      final data = response.body;
      final verificationUrl = '${data['verification_uri'] ?? ''}';
      _pending = SimklPendingAuth(
        userCode: '${data['user_code'] ?? ''}',
        verificationUrl: verificationUrl,
        completeUrl: '${data['verification_uri_complete'] ?? verificationUrl}',
        deviceCode: '${data['device_code'] ?? ''}',
      );
      _pollInterval = Duration(
        seconds: (data['interval'] as num?)?.toInt() ?? 5,
      );
      _deviceCodeExpiresAt = DateTime.now().add(
        Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 900),
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
        _status != SimklAuthStatus.pending) {
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
        _status != SimklAuthStatus.pending) {
      return;
    }
    final expiresAt = _deviceCodeExpiresAt;
    final code = _pending?.deviceCode;
    final verifier = _codeVerifier;
    if (expiresAt == null ||
        !DateTime.now().isBefore(expiresAt) ||
        code == null ||
        verifier == null) {
      cancelAuth();
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      final response = await _send(
        SimklRequest(
          path: '/oauth2/token',
          form: {
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'client_id': _clientId,
            'device_code': code,
            'code_verifier': verifier,
          },
        ),
      );
      if (_disposed || attempt != _authAttempt) return;
      if (response.statusCode < 400) {
        await _saveTokens(response.body);
        if (_disposed || attempt != _authAttempt) return;
        _clearPendingAttempt();
        _status = SimklAuthStatus.connected;
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
    _status = SimklAuthStatus.disconnected;
    if (!_disposed) notifyListeners();
  }

  Future<void> disconnect() async {
    _clearPendingAttempt();
    final token = await _storage.read(_kKeyRefresh) ?? _accessToken;
    _accessToken = null;
    await _clearStorage();
    _status = SimklAuthStatus.disconnected;
    if (!_disposed) notifyListeners();
    if (token == null) return;
    try {
      await _send(
        SimklRequest(
          path: '/oauth2/revoke',
          form: {'client_id': _clientId, 'token': token},
        ),
      );
    } on Object catch (_) {
      debugPrint('[Simkl] revoke failed');
    }
  }

  void _clearPendingAttempt() {
    _authAttempt += 1;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pending = null;
    _codeVerifier = null;
    _pollInterval = Duration.zero;
    _deviceCodeExpiresAt = null;
  }

  Future<bool> _accessTokenExpired() async {
    final expiry = int.tryParse(await _storage.read(_kKeyExpiry) ?? '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiry == null || expiry <= now + 60;
  }

  /// Exchanges the refresh token. Signs out only when Simkl rejects it: a
  /// network failure keeps the session and tries again on the next scrobble.
  Future<bool> _refresh() async {
    final attempt = _authAttempt;
    final refresh = await _storage.read(_kKeyRefresh);
    if (refresh == null || refresh.isEmpty) {
      await _signOutLocally(attempt);
      return false;
    }
    final SimklResponse response;
    try {
      response = await _send(
        SimklRequest(
          path: '/oauth2/token',
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
    _status = SimklAuthStatus.disconnected;
    notifyListeners();
  }

  Future<void> _saveTokens(Map<String, Object?> data) async {
    final accessToken = '${data['access_token'] ?? ''}';
    if (accessToken.isEmpty) throw const FormatException('No access token');
    final scope = data['scope'] as String?;
    if (scope != null && !scope.contains('media:write')) {
      debugPrint('[Simkl] token granted without write access');
    }
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
      debugPrint('[Simkl] account lookup failed');
    }
  }

  Future<String?> _fetchAccountName(String accessToken) async {
    final version = await (_appVersion ??= _resolveAppVersion());
    final response = await _api.send(
      'GET',
      Uri.parse('$_kApi/users/settings').replace(
        queryParameters: {
          'client_id': _clientId,
          'app-name': _kAppName,
          'app-version': version,
        },
      ),
      headers: {
        'user-agent': '$_kAppName/$version',
        'authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode >= 400 || response.bytes.isEmpty) return null;
    final body = await response.json();
    final user = body is Map<String, Object?> ? body['user'] : null;
    if (user is! Map<String, Object?>) return null;
    final name = user['name'];
    return name is String ? name : null;
  }

  /// Runs one at a time: Simkl holds a short per-user lock after each write.
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
    final ids = <String, Object>{
      if ((tmdbId ?? 0) > 0) 'tmdb': tmdbId!,
      if (imdbId != null && imdbId.startsWith('tt')) 'imdb': imdbId,
    };
    final isEpisode = seriesTitle != null && season != null && episode != null;
    final body = <String, Object>{
      'progress': double.parse(progress.toStringAsFixed(2)),
      isEpisode ? 'show' : 'movie': <String, Object>{
        'title': isEpisode ? seriesTitle : title,
        'year': ?year,
        if (ids.isNotEmpty) 'ids': ids,
      },
      if (isEpisode)
        'episode': <String, Object>{'season': season, 'number': episode},
    };
    return _scrobbleQueue.run(() async {
      try {
        await _sendScrobble(action, body);
      } on Object catch (_) {
        debugPrint('[Simkl] scrobble failed');
      }
    });
  }

  Future<void> _sendScrobble(String action, Map<String, Object> body) async {
    if (!isConnected) return;
    if (await _accessTokenExpired() && !await _refresh()) return;
    var response = await _postScrobble(action, body);
    if (response?.statusCode == 401) {
      if (!await _refresh()) return;
      response = await _postScrobble(action, body);
    }
    // A later event is lost without a retry, and a `stop` is what marks a title
    // watched. A missed `start` doesn't matter: the next event carries progress.
    if (response != null && _hitWriteLock(response) && action != 'start') {
      await Future<void>.delayed(_writeLockRetryDelay);
      if (_disposed) return;
      await _postScrobble(action, body);
    }
  }

  bool _hitWriteLock(SimklResponse response) =>
      response.statusCode == 429 ||
      (response.statusCode == 400 && response.error == 'RATE_LIMIT');

  Future<SimklResponse?> _postScrobble(
    String action,
    Map<String, Object> body,
  ) async {
    final token = _accessToken;
    if (token == null) return null;
    return _send(
      SimklRequest(
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
      debugPrint('[Simkl] app version unavailable');
    }
    return '1.0';
  }

  Future<SimklResponse> _send(SimklRequest request) async {
    final transport = _transport;
    if (transport != null) return transport(request);
    final version = await (_appVersion ??= _resolveAppVersion());
    final response = await _api.send(
      'POST',
      Uri.parse('$_kApi${request.path}').replace(
        queryParameters: {
          'client_id': _clientId,
          'app-name': _kAppName,
          'app-version': version,
        },
      ),
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
      return SimklResponse(response.statusCode, const <String, Object?>{});
    }
    final decoded = await response.json();
    return SimklResponse(
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
