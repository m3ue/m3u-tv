import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:m3u_tv/services/secure_storage.dart';

// Register your app at https://trakt.tv/oauth/applications and fill in these
// values before publishing. The secret is required for the device token exchange.
const _kClientId = String.fromEnvironment('TRAKT_CLIENT_ID');
const _kClientSecret = String.fromEnvironment('TRAKT_CLIENT_SECRET');

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

/// Manages Trakt OAuth via the TV device-code flow.
///
/// Call `init` once after construction to restore a persisted session.
/// Call `startDeviceAuth` to begin the flow — the UI should display
/// `pending.userCode` and `pending.verificationUrl` and show a spinner.
/// The service polls automatically and transitions to
/// `TraktAuthStatus.connected` on success.
class TraktService extends ChangeNotifier {
  TraktService({required this._storage});

  final SecureStorage _storage;
  final _http = HttpClient();

  TraktAuthStatus _status = TraktAuthStatus.disconnected;
  TraktPendingAuth? _pending;
  Timer? _pollTimer;
  String? _accessToken;

  TraktAuthStatus get status => _status;
  TraktPendingAuth? get pending => _pending;

  // False when the developer hasn't yet filled in the client credentials.
  bool get isConfigured => _kClientId.isNotEmpty;

  Future<void> init() async {
    _accessToken = await _storage.read(_kKeyAccess);
    if (_accessToken == null) return;
    final expiryStr = await _storage.read(_kKeyExpiry);
    final expiry = int.tryParse(expiryStr ?? '');
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiry != null && expiry > nowEpoch + 60) {
      _status = TraktAuthStatus.connected;
    } else {
      await _tryRefresh();
    }
    notifyListeners();
  }

  Future<void> startDeviceAuth() async {
    if (!isConfigured) return;
    _status = TraktAuthStatus.pending;
    notifyListeners();
    try {
      final data = await _post('/oauth/device/code', {'client_id': _kClientId});
      _pending = TraktPendingAuth(
        userCode: '${data['user_code'] ?? ''}',
        verificationUrl: '${data['verification_url'] ?? ''}',
        deviceCode: '${data['device_code'] ?? ''}',
      );
      final interval = (data['interval'] as num?)?.toInt() ?? 5;
      notifyListeners();
      _pollTimer = Timer.periodic(Duration(seconds: interval), (_) => _poll());
    } on Object catch (_) {
      _status = TraktAuthStatus.disconnected;
      _pending = null;
      notifyListeners();
    }
  }

  Future<void> _poll() async {
    if (_status == TraktAuthStatus.connected) return;
    final code = _pending?.deviceCode;
    if (code == null) return;
    try {
      final data = await _post('/oauth/device/token', {
        'code': code,
        'client_id': _kClientId,
        'client_secret': _kClientSecret,
      });
      await _saveTokens(data);
    } on _TraktPendingException {
      // authorization_pending — keep polling
    } on Object catch (_) {
      // Guard against a stale poll that fires after _saveTokens already
      // completed (timer cancel and token write are async — a queued callback
      // can still execute and receive a 409 "already used" from Trakt).
      if (_status != TraktAuthStatus.connected) {
        cancelAuth();
      }
    }
  }

  Future<void> _tryRefresh() async {
    final refresh = await _storage.read(_kKeyRefresh);
    if (refresh == null || refresh.isEmpty) {
      await _clearStorage();
      return;
    }
    try {
      final data = await _post('/oauth/token', {
        'refresh_token': refresh,
        'client_id': _kClientId,
        'client_secret': _kClientSecret,
        'grant_type': 'refresh_token',
      });
      await _saveTokens(data);
    } on Object catch (_) {
      await _clearStorage();
    }
  }

  Future<void> _saveTokens(Map<String, Object?> data) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _accessToken = '${data['access_token'] ?? ''}';
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 7776000;
    final expiry = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expiresIn;
    await _storage.write(_kKeyAccess, _accessToken!);
    await _storage.write(_kKeyRefresh, '${data['refresh_token'] ?? ''}');
    await _storage.write(_kKeyExpiry, '$expiry');
    _status = TraktAuthStatus.connected;
    _pending = null;
    notifyListeners();
  }

  void cancelAuth() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pending = null;
    _status = TraktAuthStatus.disconnected;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pending = null;
    _accessToken = null;
    await _clearStorage();
    _status = TraktAuthStatus.disconnected;
    notifyListeners();
  }

  Future<void> _clearStorage() async {
    await _storage.delete(_kKeyAccess);
    await _storage.delete(_kKeyRefresh);
    await _storage.delete(_kKeyExpiry);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object> body,
  ) async {
    final encoded = utf8.encode(jsonEncode(body));
    final req = await _http.postUrl(Uri.parse('$_kApi$path'));
    req
      ..headers.contentType = ContentType.json
      ..headers.set('trakt-api-version', '2')
      ..headers.set('trakt-api-key', _kClientId)
      ..contentLength = encoded.length
      ..add(encoded);
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    // 400 = authorization_pending; 404 = expired or already used
    if (res.statusCode == 400 || res.statusCode == 404) {
      throw _TraktPendingException();
    }
    if (res.statusCode >= 400) {
      throw Exception('Trakt HTTP ${res.statusCode}');
    }
    return jsonDecode(text) as Map<String, Object?>;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _http.close();
    super.dispose();
  }
}

class _TraktPendingException implements Exception {}
