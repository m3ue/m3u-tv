import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Manages authentication state, mirroring the RN XtreamContext behavior.
///
/// Credentials are stored under the `m3ue_tv_credentials` key in secure storage.
/// The active viewer is stored under `m3ue_tv_active_viewer`.
/// Auth requires `user_info.auth === 1` and a present `m3u_editor` object.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier({required this.xtreamService, required this.secureStorage});

  static const _credentialsKey = 'm3ue_tv_credentials';

  final XtreamService xtreamService;
  final SecureStorage secureStorage;

  bool _isConfigured = false;
  XtreamAuthResponse? _authResponse;
  String? _error;
  bool _isLoading = false;

  bool get isConfigured => _isConfigured;
  XtreamAuthResponse? get authResponse => _authResponse;
  String? get error => _error;
  bool get isLoading => _isLoading;

  /// Connects to an Xtream/m3u-editor server with the given credentials.
  ///
  /// Returns true on success. On failure, sets [error] and returns false.
  /// Credentials are persisted to secure storage on success.
  Future<bool> connect(UserCredentials credentials) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await xtreamService.authenticate(credentials);
      await secureStorage.write(
        _credentialsKey,
        jsonEncode({
          'server': credentials.server,
          'username': credentials.username,
          'password': credentials.password,
        }),
      );

      _isConfigured = true;
      _authResponse = response;
      _isLoading = false;
      notifyListeners();
      return true;
    } on XtreamAuthException catch (e) {
      _error = _redact(e.message, credentials);
      _isLoading = false;
      notifyListeners();
      return false;
    } on Object catch (e) {
      _error = _redact(userFacingXtreamError(e), credentials);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Disconnects from the server, clearing all auth state and stored credentials.
  Future<void> disconnect() async {
    await secureStorage.delete(_credentialsKey);
    xtreamService.clearCredentials();
    _isConfigured = false;
    _authResponse = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Attempts to restore credentials from secure storage and reconnect.
  ///
  /// Returns true if credentials were found and reconnection succeeded.
  Future<bool> loadSavedCredentials() async {
    final saved = await secureStorage.read(_credentialsKey);
    if (saved == null) return false;

    try {
      final json = jsonDecode(saved) as Map<String, Object?>;
      final credentials = UserCredentials(
        server: '${json['server'] ?? ''}',
        username: '${json['username'] ?? ''}',
        password: '${json['password'] ?? ''}',
      );
      return await connect(credentials);
    } on Object catch (_) {
      return false;
    }
  }

  /// Clears the current error message.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _redact(String message, UserCredentials credentials) {
    var redacted = message;
    if (credentials.password.isNotEmpty) {
      redacted = redacted.replaceAll(credentials.password, '[redacted]');
    }
    if (credentials.username.length > 2) {
      redacted = redacted.replaceAll(credentials.username, '[redacted]');
    }
    return redacted;
  }
}
