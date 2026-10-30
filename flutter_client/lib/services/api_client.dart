import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:m3u_tv/services/json_isolate.dart';

/// Shared JSON-over-HTTP client for the app's REST services (editor `/api/tv`,
/// Trakt, IntroDB, AIOStreams, release notes, ...), so each one doesn't
/// re-implement encode, send, timeout, status check and decode.
///
/// Built on `package:http`, which picks dart:io's pooled `HttpClient` on
/// native and the browser's networking on the web, so callers need no
/// platform branch. Large bodies decode on a background isolate (see
/// [decodeJsonBytesOffMainIsolate]). Inject a `MockClient` in tests.
///
/// Not for the Xtream catalog downloads: those deliberately have no response
/// timeout and stream raw bytes to their own parse isolate.
class ApiClient {
  ApiClient({http.Client? client, this.timeout = defaultTimeout})
    : _client = client ?? http.Client();

  static const Duration defaultTimeout = Duration(seconds: 15);

  final http.Client _client;

  /// Default per-request bound, applied to both receiving the response
  /// headers and reading the body, so a stalled server can't leave a caller
  /// waiting forever.
  final Duration timeout;

  /// Sends a request and returns the response whatever its status. Use this
  /// when the caller interprets status codes itself; otherwise prefer
  /// [getJson] / [postJson] / [deleteJson], which throw [ApiException] on an
  /// error status.
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Object? json,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    final limit = timeout ?? this.timeout;
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (json != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..bodyBytes = utf8.encode(jsonEncode(json));
    }
    final response = await _client.send(request).timeout(limit);
    final bytes = await response.stream.toBytes().timeout(limit);
    return ApiResponse(uri: uri, statusCode: response.statusCode, bytes: bytes);
  }

  Future<Object?> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _json('GET', uri, headers: headers, timeout: timeout);

  Future<Object?> postJson(
    Uri uri,
    Object? body, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _json('POST', uri, body: body, headers: headers, timeout: timeout);

  Future<Object?> deleteJson(
    Uri uri,
    Object? body, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) => _json('DELETE', uri, body: body, headers: headers, timeout: timeout);

  Future<Object?> _json(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    final response = await send(
      method,
      uri,
      json: body,
      headers: headers,
      timeout: timeout,
    );
    response.throwIfError();
    return response.json();
  }

  void close() => _client.close();
}

class ApiResponse {
  const ApiResponse({
    required this.uri,
    required this.statusCode,
    required this.bytes,
  });

  final Uri uri;
  final int statusCode;
  final Uint8List bytes;

  bool get isError => statusCode >= 400;

  String get text => utf8.decode(bytes, allowMalformed: true);

  /// The decoded JSON body, or null for an empty one.
  Future<Object?> json() =>
      bytes.isEmpty ? Future.value() : decodeJsonBytesOffMainIsolate(bytes);

  void throwIfError() {
    if (isError) throw ApiException(statusCode, text, uri);
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.body, this.uri);

  final int statusCode;
  final String body;
  final Uri uri;

  @override
  String toString() => 'ApiException($statusCode)';
}
