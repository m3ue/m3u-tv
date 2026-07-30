// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/secure_storage.dart';

// Register your public app at https://trakt.tv/oauth/applications and pass the
// client id with TRAKT_CLIENT_ID when building.
const _clientIdFromEnvironment = String.fromEnvironment('TRAKT_CLIENT_ID');

const _kApi = 'https://api.trakt.tv';
const _kKeyAccess = 'trakt_access_token';
const _kKeyRefresh = 'trakt_refresh_token';
const _kKeyExpiry = 'trakt_token_expiry';

enum TraktAuthStatus { disconnected, pending, connected }

class TraktPendingAuth {
  const TraktPendingAuth({
    required this.userCode,
    required this.verificationUrl,
    required this.deviceCode,
  });

  final String userCode;
  final String verificationUrl;
  final String deviceCode;
}

typedef TraktTransport = Future<TraktResponse> Function(TraktRequest request);
typedef TraktCodeVerifierFactory = String Function();

String _generateCodeVerifier() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _codeChallenge(String verifier) => base64UrlEncode(
  sha256.convert(ascii.encode(verifier)).bytes,
).replaceAll('=', '');

class TraktRequest {
  const TraktRequest({
    required this.path,
    required this.body,
    this.accessToken,
  });

  final String path;
  final Map<String, Object> body;
  final String? accessToken;
}

class TraktResponse {
  const TraktResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

/// Manages Trakt OAuth via the TV device-code flow.
///
/// Call `init` once after construction to restore a persisted session.
/// Call `startDeviceAuth` to begin the flow. The UI should display
/// `pending.userCode` and `pending.verificationUrl` and show a spinner.
/// The service polls automatically and transitions to
/// `TraktAuthStatus.connected` on success.
class TraktService extends ChangeNotifier {
  // Keep the public constructor parameter names stable for callers.
  TraktService({
    required SecureStorage storage,
    String clientId = _clientIdFromEnvironment,
    TraktTransport? transport,
    TraktCodeVerifierFactory? codeVerifierFactory,
  }) : _storage = storage,
       _clientId = clientId,
       _transport = transport,
       _codeVerifierFactory = codeVerifierFactory ?? _generateCodeVerifier;

  final SecureStorage _storage;
  final String _clientId;
  final TraktTransport? _transport;
  final TraktCodeVerifierFactory _codeVerifierFactory;
  final _http = HttpClient();

  TraktAuthStatus _status = TraktAuthStatus.disconnected;
  TraktPendingAuth? _pending;
  Timer? _pollTimer;
  String? _accessToken;
  String? _codeVerifier;
  Duration _pollInterval = Duration.zero;
  DateTime? _deviceCodeExpiresAt;
  final _tokenQueue = SerialQueue();
  var _authAttempt = 0;
  var _disposed = false;

  TraktAuthStatus get status => _status;
  TraktPendingAuth? get pending => _pending;

  @visibleForTesting
  Duration get pollIntervalForTesting => _pollInterval;

  // False when the public client id was not supplied.
  bool get isConfigured => _clientId.isNotEmpty;

  Future<void> init() async {
    final attempt = _authAttempt;
    final accessToken = await _storage.read(_kKeyAccess);
    if (_disposed || attempt != _authAttempt) return;
    _accessToken = accessToken;
    if (_accessToken == null) return;
    final expiryStr = await _storage.read(_kKeyExpiry);
    if (_disposed || attempt != _authAttempt) return;
    final expiry = int.tryParse(expiryStr ?? '');
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiry != null && expiry > nowEpoch + 60) {
      _status = TraktAuthStatus.connected;
    } else {
      await _tryRefresh();
    }
    if (_disposed || attempt != _authAttempt) return;
    notifyListeners();
  }

  Future<void> startDeviceAuth() async {
    if (!isConfigured || _disposed) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    final attempt = ++_authAttempt;
    final verifier = _codeVerifierFactory();
    _codeVerifier = verifier;
    _pending = null;
    _status = TraktAuthStatus.pending;
    notifyListeners();
    try {
      final data = await _post('/oauth/device/code', {
        'client_id': _clientId,
        'code_challenge': _codeChallenge(verifier),
        'code_challenge_method': 'S256',
      });
      if (_disposed || attempt != _authAttempt) return;
      _pending = TraktPendingAuth(
        userCode: '${data['user_code'] ?? ''}',
        verificationUrl: '${data['verification_url'] ?? ''}',
        deviceCode: '${data['device_code'] ?? ''}',
      );
      final interval = (data['interval'] as num?)?.toInt() ?? 5;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 600;
      _pollInterval = Duration(seconds: interval);
      _deviceCodeExpiresAt = DateTime.now().add(
        Duration(seconds: expiresIn),
      );
      notifyListeners();
      _schedulePoll(attempt);
    } on Object catch (_) {
      if (_disposed || attempt != _authAttempt) return;
      _clearPendingAttempt();
      _status = TraktAuthStatus.disconnected;
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<void> pollForTesting() => _poll(_authAttempt);

  void _schedulePoll(int attempt) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_disposed ||
        attempt != _authAttempt ||
        _status != TraktAuthStatus.pending) {
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
    if (_disposed || attempt != _authAttempt) return;
    if (_status != TraktAuthStatus.pending) return;
    final expiresAt = _deviceCodeExpiresAt;
    if (expiresAt == null || !DateTime.now().isBefore(expiresAt)) {
      cancelAuth();
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    final code = _pending?.deviceCode;
    final verifier = _codeVerifier;
    if (code == null || verifier == null) return;
    try {
      final data = await _post(
        '/oauth/device/token',
        {
          'code': code,
          'client_id': _clientId,
          'code_verifier': verifier,
        },
        isPollEndpoint: true,
      );
      if (_disposed || attempt != _authAttempt) return;
      await _saveTokens(data, expectedAttempt: attempt);
    } on _TraktPendingException {
      _schedulePoll(attempt);
    } on _TraktSlowDownException {
      _pollInterval += const Duration(seconds: 5);
      _schedulePoll(attempt);
    } on Object catch (_) {
      // A queued callback from an old attempt must not cancel current auth.
      if (!_disposed &&
          attempt == _authAttempt &&
          _status != TraktAuthStatus.connected) {
        cancelAuth();
      }
    }
  }

  Future<void> _tryRefresh() async {
    final attempt = _authAttempt;
    final refresh = await _storage.read(_kKeyRefresh);
    if (refresh == null || refresh.isEmpty) {
      await _clearStorage();
      return;
    }
    try {
      final data = await _post('/oauth/token', {
        'refresh_token': refresh,
        'client_id': _clientId,
        'grant_type': 'refresh_token',
      });
      if (_disposed || attempt != _authAttempt) return;
      await _saveTokens(data, expectedAttempt: attempt);
    } on Object catch (_) {
      if (_disposed || attempt != _authAttempt) return;
      await _clearStorage();
    }
  }

  Future<void> _saveTokens(
    Map<String, Object?> data, {
    required int expectedAttempt,
  }) => _tokenQueue.run(() async {
    if (_disposed || expectedAttempt != _authAttempt) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    final previous = await _readStoredTokens();
    if (_disposed || expectedAttempt != _authAttempt) return;
    final accessToken = '${data['access_token'] ?? ''}';
    final refreshToken = '${data['refresh_token'] ?? ''}';
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 7776000;
    final expiry = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expiresIn;
    try {
      await _storage.write(_kKeyAccess, accessToken);
      if (_disposed || expectedAttempt != _authAttempt) {
        await _restoreStoredTokens(previous);
        return;
      }
      await _storage.write(_kKeyRefresh, refreshToken);
      if (_disposed || expectedAttempt != _authAttempt) {
        await _restoreStoredTokens(previous);
        return;
      }
      await _storage.write(_kKeyExpiry, '$expiry');
      if (_disposed || expectedAttempt != _authAttempt) {
        await _restoreStoredTokens(previous);
        return;
      }
    } on Object {
      await _restoreStoredTokens(previous);
      rethrow;
    }
    _clearPendingAttempt();
    _accessToken = accessToken;
    _status = TraktAuthStatus.connected;
    notifyListeners();
  });

  void cancelAuth() {
    _clearPendingAttempt();
    _status = TraktAuthStatus.disconnected;
    if (!_disposed) notifyListeners();
  }

  Future<void> disconnect() async {
    _clearPendingAttempt();
    await _tokenQueue.run(() async {
      _accessToken = null;
      await _clearStorage();
      _status = TraktAuthStatus.disconnected;
      if (!_disposed) notifyListeners();
    });
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

  Future<Map<String, String?>> _readStoredTokens() async => {
    _kKeyAccess: await _storage.read(_kKeyAccess),
    _kKeyRefresh: await _storage.read(_kKeyRefresh),
    _kKeyExpiry: await _storage.read(_kKeyExpiry),
  };

  Future<void> _restoreStoredTokens(Map<String, String?> tokens) async {
    for (final entry in tokens.entries) {
      final value = entry.value;
      if (value == null) {
        await _storage.delete(entry.key);
      } else {
        await _storage.write(entry.key, value);
      }
    }
  }

  Future<void> _clearStorage() async {
    await _storage.delete(_kKeyAccess);
    await _storage.delete(_kKeyRefresh);
    await _storage.delete(_kKeyExpiry);
  }

  /// Scrobbles the current playback position to Trakt.
  ///
  /// [action] is one of `'start'`, `'pause'`, or `'stop'`.
  /// Pass [seriesTitle], [season], and [episode] for TV episodes; omit for movies.
  /// [progress] is 0 to 100.
  ///
  /// Errors are silently ignored because scrobbling is best-effort.
  Future<void> scrobble({
    required String action,
    required String title,
    String? seriesTitle,
    int? season,
    int? episode,
    int? tmdbId,
    String? imdbId,
    required double progress,
  }) async {
    final token = _accessToken;
    if (_status != TraktAuthStatus.connected || token == null) return;
    final ids = <String, Object>{
      if ((tmdbId ?? 0) > 0) 'tmdb': tmdbId!,
      if (imdbId != null && imdbId.startsWith('tt')) 'imdb': imdbId,
    };
    final Map<String, Object> body;
    if (seriesTitle != null && season != null && episode != null) {
      body = {
        'show': <String, Object>{
          'title': seriesTitle,
          if (ids.isNotEmpty) 'ids': ids,
        },
        'episode': <String, Object>{'season': season, 'number': episode},
        'progress': progress,
      };
    } else {
      body = {
        'movie': <String, Object>{
          'title': title,
          if (ids.isNotEmpty) 'ids': ids,
        },
        'progress': progress,
      };
    }
    try {
      await _post('/scrobble/$action', body, accessToken: token);
      debugPrint('[Trakt] scrobble succeeded');
    } on Object catch (_) {
      debugPrint('[Trakt] scrobble failed');
    }
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object> body, {
    String? accessToken,
    bool isPollEndpoint = false,
  }) async {
    final transport = _transport;
    if (transport != null) {
      final res = await transport(
        TraktRequest(path: path, body: body, accessToken: accessToken),
      );
      return _handleResponse(
        statusCode: res.statusCode,
        body: res.body,
        isPollEndpoint: isPollEndpoint,
      );
    }
    final encoded = utf8.encode(jsonEncode(body));
    final req = await _http.postUrl(Uri.parse('$_kApi$path'));
    req
      ..headers.contentType = ContentType.json
      ..headers.set('trakt-api-version', '2')
      ..headers.set('trakt-api-key', _clientId);
    if (accessToken != null) {
      req.headers.set('Authorization', 'Bearer $accessToken');
    }
    req
      ..contentLength = encoded.length
      ..add(encoded);
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    final bodyJson = text.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;
    return _handleResponse(
      statusCode: res.statusCode,
      body: bodyJson,
      isPollEndpoint: isPollEndpoint,
    );
  }

  Map<String, Object?> _handleResponse({
    required int statusCode,
    required Map<String, Object?> body,
    required bool isPollEndpoint,
  }) {
    if (isPollEndpoint) {
      final error = body['error'];
      if (statusCode == 429 || error == 'slow_down') {
        throw _TraktSlowDownException();
      }
      if (statusCode == 400 &&
          (error == null || error == 'authorization_pending')) {
        throw _TraktPendingException();
      }
    }
    if (statusCode >= 400) {
      throw const _TraktHttpException();
    }
    return body;
  }

  @override
  void dispose() {
    _disposed = true;
    _clearPendingAttempt();
    _http.close();
    super.dispose();
  }
}

class _TraktPendingException implements Exception {}

class _TraktSlowDownException implements Exception {}

class _TraktHttpException implements Exception {
  const _TraktHttpException();
}
