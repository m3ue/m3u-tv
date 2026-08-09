// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Hide the app's own ContentType enum (live/vod/episode/aiostreams) so it
// doesn't shadow dart:io's ContentType class used below for HTTP headers.
import 'package:m3u_tv/services/domain_models.dart' hide ContentType;

enum DevicePairingStatus { idle, pending, approved, error }

class DevicePairingPending {
  const DevicePairingPending({
    required this.userCode,
    required this.verificationUri,
    required this.deviceCode,
  });

  final String userCode;
  final String verificationUri;
  final String deviceCode;
}

class DevicePairingRequest {
  const DevicePairingRequest({
    required this.server,
    required this.path,
    required this.body,
  });

  final String server;
  final String path;
  final Map<String, Object> body;
}

class DevicePairingResponse {
  const DevicePairingResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

typedef DevicePairingTransport =
    Future<DevicePairingResponse> Function(DevicePairingRequest request);

/// Manages a Trakt-style device pairing handshake against the user's own
/// m3u-editor server: request a short-lived code, show it (+ a QR code to the
/// admin panel), and poll until an admin approves it and hands back the
/// username/password of the PlaylistAuth they chose.
///
/// This is a one-shot handshake — on success, `result` holds the credentials
/// for the caller to persist via `AuthNotifier.connect()`. This service does
/// no storage of its own.
class DevicePairingService extends ChangeNotifier {
  DevicePairingService({DevicePairingTransport? transport})
    : _transport = transport;

  final DevicePairingTransport? _transport;
  final _http = HttpClient();

  DevicePairingStatus _status = DevicePairingStatus.idle;
  DevicePairingPending? _pending;
  UserCredentials? _result;
  Timer? _pollTimer;
  Duration _pollInterval = const Duration(seconds: 5);
  DateTime? _codeExpiresAt;
  var _attempt = 0;
  var _disposed = false;

  DevicePairingStatus get status => _status;
  DevicePairingPending? get pending => _pending;
  UserCredentials? get result => _result;

  @visibleForTesting
  Duration get pollIntervalForTesting => _pollInterval;

  Future<void> start(String server) async {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    final attempt = ++_attempt;
    final normalizedServer = normalizeServerUrl(server);
    _pending = null;
    _result = null;
    _status = DevicePairingStatus.pending;
    notifyListeners();
    try {
      final data = await _post(normalizedServer, '/api/device/code', {});
      if (_disposed || attempt != _attempt) return;
      _pending = DevicePairingPending(
        userCode: '${data['user_code'] ?? ''}',
        verificationUri: '${data['verification_uri'] ?? ''}',
        deviceCode: '${data['device_code'] ?? ''}',
      );
      final interval = (data['interval'] as num?)?.toInt() ?? 5;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 600;
      _pollInterval = Duration(seconds: interval);
      _codeExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      notifyListeners();
      _schedulePoll(attempt, normalizedServer);
    } on Object catch (_) {
      if (_disposed || attempt != _attempt) return;
      _status = DevicePairingStatus.error;
      notifyListeners();
    }
  }

  void cancel() {
    _attempt += 1;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pending = null;
    _codeExpiresAt = null;
    _status = DevicePairingStatus.idle;
    if (!_disposed) notifyListeners();
  }

  void _schedulePoll(int attempt, String server) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_disposed ||
        attempt != _attempt ||
        _status != DevicePairingStatus.pending) {
      return;
    }
    final expiresAt = _codeExpiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _fail(attempt);
      return;
    }
    final delay = remaining < _pollInterval ? remaining : _pollInterval;
    _pollTimer = Timer(delay, () => unawaited(_poll(attempt, server)));
  }

  @visibleForTesting
  Future<void> pollForTesting(String server) => _poll(_attempt, server);

  Future<void> _poll(int attempt, String server) async {
    if (_disposed || attempt != _attempt) return;
    if (_status != DevicePairingStatus.pending) return;
    final expiresAt = _codeExpiresAt;
    if (expiresAt == null || !DateTime.now().isBefore(expiresAt)) {
      _fail(attempt);
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    final deviceCode = _pending?.deviceCode;
    if (deviceCode == null) return;
    try {
      final data = await _post(server, '/api/device/token', {
        'device_code': deviceCode,
      });
      if (_disposed || attempt != _attempt) return;
      final status = '${data['status'] ?? ''}';
      switch (status) {
        case 'approved':
          _result = UserCredentials(
            server: server,
            username: '${data['username'] ?? ''}',
            password: '${data['password'] ?? ''}',
          );
          _pollTimer?.cancel();
          _pollTimer = null;
          _status = DevicePairingStatus.approved;
          notifyListeners();
        case 'slow_down':
          final interval = (data['interval'] as num?)?.toInt();
          _pollInterval = interval != null
              ? Duration(seconds: interval)
              : _pollInterval + const Duration(seconds: 5);
          _schedulePoll(attempt, server);
        case 'expired':
        case 'denied':
          _fail(attempt);
        default:
          _schedulePoll(attempt, server);
      }
    } on Object catch (_) {
      if (!_disposed &&
          attempt == _attempt &&
          _status != DevicePairingStatus.approved) {
        _schedulePoll(attempt, server);
      }
    }
  }

  void _fail(int attempt) {
    if (_disposed || attempt != _attempt) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    _status = DevicePairingStatus.error;
    notifyListeners();
  }

  Future<Map<String, Object?>> _post(
    String server,
    String path,
    Map<String, Object> body,
  ) async {
    final transport = _transport;
    if (transport != null) {
      final res = await transport(
        DevicePairingRequest(server: server, path: path, body: body),
      );
      return res.body;
    }
    final encoded = utf8.encode(jsonEncode(body));
    final req = await _http.postUrl(Uri.parse('$server$path'));
    req.headers.contentType = ContentType.json;
    req
      ..contentLength = encoded.length
      ..add(encoded);
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    return text.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>;
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _http.close();
    super.dispose();
  }
}
