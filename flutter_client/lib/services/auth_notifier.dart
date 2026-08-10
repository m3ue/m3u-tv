import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/xtream_service.dart';

class AuthSessionSnapshot {
  const AuthSessionSnapshot._(
    this._isConfigured,
    this._authResponse,
    this._credentials,
    this._error,
    this._xtreamSession,
  );

  final bool _isConfigured;
  final XtreamAuthResponse? _authResponse;
  final UserCredentials? _credentials;
  final String? _error;
  final XtreamSessionSnapshot _xtreamSession;
}

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
  UserCredentials? _credentials;
  String? _error;
  bool _isLoading = false;
  int _connectionGeneration = 0;
  final SerialQueue _credentialPersistenceQueue = SerialQueue();

  bool get isConfigured => _isConfigured;
  XtreamAuthResponse? get authResponse => _authResponse;

  /// The credentials used for the current session. Null when not connected.
  UserCredentials? get credentials => _credentials;

  String? get error => _error;
  bool get isLoading => _isLoading;

  AuthSessionSnapshot snapshotSession() => AuthSessionSnapshot._(
    _isConfigured,
    _authResponse,
    _credentials,
    _error,
    xtreamService.snapshotSession(),
  );

  Future<void> restoreSession(AuthSessionSnapshot snapshot) async {
    _connectionGeneration += 1;
    final credentials = snapshot._credentials;
    try {
      await _persistCredentials(credentials);
    } finally {
      xtreamService.restoreSession(snapshot._xtreamSession);
      _isConfigured = snapshot._isConfigured;
      _authResponse = snapshot._authResponse;
      _credentials = credentials;
      _error = snapshot._error;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Connects to an Xtream/m3u-editor server with the given credentials.
  ///
  /// Returns true on success. On failure, sets [error] and returns false.
  /// Credentials are persisted to secure storage on success.
  Future<bool> connect(
    UserCredentials credentials, {
    bool Function()? isCurrent,
    bool persistCredentials = true,
    bool publishSession = true,
  }) async {
    final connectionGeneration = ++_connectionGeneration;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await xtreamService.authenticate(credentials);
      if (!_isCurrentConnection(connectionGeneration, isCurrent)) {
        _finishStaleConnection(connectionGeneration);
        return false;
      }
      if (persistCredentials) await _persistCredentials(credentials);
      if (!_isCurrentConnection(connectionGeneration, isCurrent)) {
        _finishStaleConnection(connectionGeneration);
        return false;
      }

      _isConfigured = true;
      _authResponse = response;
      _credentials = credentials;
      _isLoading = false;
      if (publishSession) notifyListeners();
      return true;
    } on XtreamAuthException catch (e) {
      if (!_isCurrentConnection(connectionGeneration, isCurrent)) {
        _finishStaleConnection(connectionGeneration);
        return false;
      }
      _error = _redact(e.message, credentials);
      _isLoading = false;
      notifyListeners();
      return false;
    } on Object catch (e) {
      if (!_isCurrentConnection(connectionGeneration, isCurrent)) {
        _finishStaleConnection(connectionGeneration);
        return false;
      }
      _error = _redact(userFacingXtreamError(e), credentials);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> persistSession() async {
    final credentials = _credentials;
    if (credentials == null) return;
    await _persistCredentials(credentials);
  }

  void publishSession() => notifyListeners();

  /// Disconnects from the server, clearing all auth state and stored credentials.
  Future<void> disconnect() async {
    _connectionGeneration += 1;
    await _persistCredentials(null);
    xtreamService.clearCredentials();
    _isConfigured = false;
    _authResponse = null;
    _credentials = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Attempts to restore credentials from secure storage and reconnect.
  ///
  /// Returns true if credentials were found and reconnection succeeded.
  Future<bool> loadSavedCredentials({bool Function()? isCurrent}) async {
    await _credentialPersistenceQueue.drained;
    final saved = await secureStorage.read(_credentialsKey);
    if (saved == null) return false;

    try {
      final json = jsonDecode(saved) as Map<String, Object?>;
      final credentials = UserCredentials(
        server: '${json['server'] ?? ''}',
        username: '${json['username'] ?? ''}',
        password: '${json['password'] ?? ''}',
      );
      return await connect(credentials, isCurrent: isCurrent);
    } on Object catch (_) {
      return false;
    }
  }

  /// Clears the current error message.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  bool _isCurrentConnection(
    int connectionGeneration,
    bool Function()? isCurrent,
  ) =>
      connectionGeneration == _connectionGeneration &&
      (isCurrent?.call() ?? true);

  void _finishStaleConnection(int connectionGeneration) {
    if (connectionGeneration != _connectionGeneration) return;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persistCredentials(UserCredentials? credentials) =>
      _credentialPersistenceQueue.run(() async {
        if (credentials == null) {
          await secureStorage.delete(_credentialsKey);
          return;
        }
        await secureStorage.write(
          _credentialsKey,
          jsonEncode({
            'server': credentials.server,
            'username': credentials.username,
            'password': credentials.password,
          }),
        );
      });

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
