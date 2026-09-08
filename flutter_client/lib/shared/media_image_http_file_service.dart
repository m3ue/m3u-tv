import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:m3u_tv/services/device_performance.dart';

/// [HttpFileService] tuned for poster/backdrop fan-out.
///
/// flutter_cache_manager's default builds a bare `http.Client()` per cache
/// manager and hard-codes `concurrentFetches = 10`. On a cold start every home
/// rail fires its poster requests at once; requests queued behind the limit
/// lose races against transient network hiccups, and nothing retries
/// (the `ResilientMediaImage` widget re-adds that by hand). This service:
///
/// * shares one keep-alive [HttpClient] with an explicit per-host connection
///   cap, so sockets are reused instead of renegotiated per image;
/// * scales `concurrentFetches` to the device tier - a weak TV box floods its
///   tiny socket budget and its decoder if it tries 10 at once;
/// * drains and releases non-2xx responses immediately (stale poster URLs 404
///   in bursts) so their connections return to the pool right away.
class MediaImageHttpFileService extends HttpFileService {
  factory MediaImageHttpFileService() {
    final reduced = DevicePerformance.isReduced;
    final httpClient = HttpClient()
      ..maxConnectionsPerHost = reduced ? 4 : 8
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    return MediaImageHttpFileService._(_DrainingClient(IOClient(httpClient)));
  }

  MediaImageHttpFileService._(this._client) : super(httpClient: _client) {
    concurrentFetches = DevicePerformance.isReduced ? 4 : 8;
  }

  final http.Client _client;

  void close() => _client.close();
}

/// Releases the socket for any non-2xx response instead of letting
/// flutter_cache_manager throw with the body still open.
class _DrainingClient extends http.BaseClient {
  _DrainingClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    unawaited(response.stream.drain<void>().catchError((_) {}));
    if (kDebugMode) {
      debugPrint(
        '[MediaImage] ${response.statusCode} for ${request.url} (drained)',
      );
    }
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      response.statusCode,
      contentLength: 0,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
