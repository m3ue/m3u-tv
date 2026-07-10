import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/services/domain_models.dart';

enum StreamResolveMode { directPlay, transcode, unsupported }

enum StreamResolveFailure { rejected }

class StreamResolveRequest {
  const StreamResolveRequest({
    required this.type,
    required this.streamId,
    required this.clientCapabilities,
    this.catchupStart,
    this.catchupDurationMinutes,
    String? catchupFormat,
  }) : catchupFormat = catchupFormat == 'ts' || catchupFormat == 'm3u8'
           ? catchupFormat
           : null;

  final String type;
  final int streamId;
  final ClientCapabilities clientCapabilities;
  final DateTime? catchupStart;
  final int? catchupDurationMinutes;
  final String? catchupFormat;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'stream_id': streamId,
    'client_capabilities': clientCapabilities.toJson(),
    if (catchupStart != null)
      'catchup_start': catchupStart!.toUtc().toIso8601String(),
    if (catchupDurationMinutes != null)
      'catchup_duration_minutes': catchupDurationMinutes,
    if (catchupFormat != null) 'catchup_format': catchupFormat,
  };
}

class StreamSourceInfo {
  const StreamSourceInfo({
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.width,
    this.height,
    this.bitrateKbps,
    this.hdr,
  });

  factory StreamSourceInfo.fromJson(Map<String, Object?> json) {
    return StreamSourceInfo(
      videoCodec: json['video_codec'] as String?,
      audioCodec: json['audio_codec'] as String?,
      container: json['container'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      bitrateKbps: json['bitrate_kbps'] as int?,
      hdr: json['hdr'] as bool?,
    );
  }

  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final int? width;
  final int? height;
  final int? bitrateKbps;
  final bool? hdr;
}

class StreamOutputInfo {
  const StreamOutputInfo({
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.maxHeight,
    this.maxBitrateKbps,
    this.hdr,
  });

  factory StreamOutputInfo.fromJson(Map<String, Object?> json) {
    return StreamOutputInfo(
      videoCodec: json['video_codec'] as String?,
      audioCodec: json['audio_codec'] as String?,
      container: json['container'] as String?,
      maxHeight: json['max_height'] as int?,
      maxBitrateKbps: json['max_bitrate_kbps'] as int?,
      hdr: json['hdr'] as bool?,
    );
  }

  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final int? maxHeight;
  final int? maxBitrateKbps;
  final bool? hdr;
}

class StreamResolveResponse {
  const StreamResolveResponse({
    required this.mode,
    this.url,
    this.reason,
    this.source,
    this.output,
    this.failure,
  });

  factory StreamResolveResponse.fromJson(Map<String, Object?> json) {
    final mode = switch (json['mode']) {
      'direct_play' => StreamResolveMode.directPlay,
      'transcode' => StreamResolveMode.transcode,
      'unsupported' => StreamResolveMode.unsupported,
      final value => throw FormatException('Unknown resolve mode: $value'),
    };
    return StreamResolveResponse(
      mode: mode,
      url: json['url'] as String?,
      reason: json['reason'] as String?,
      source: json['source'] is Map
          ? StreamSourceInfo.fromJson(
              Map<String, Object?>.from(json['source']! as Map),
            )
          : null,
      output: json['output'] is Map
          ? StreamOutputInfo.fromJson(
              Map<String, Object?>.from(json['output']! as Map),
            )
          : null,
    );
  }

  final StreamResolveMode mode;
  final String? url;
  final String? reason;
  final StreamSourceInfo? source;
  final StreamOutputInfo? output;
  final StreamResolveFailure? failure;
}

// ignore: one_member_abstracts
abstract class StreamResolutionService {
  Future<StreamResolveResponse?> resolve(StreamResolveRequest request);
}

class ProductionStreamResolutionService implements StreamResolutionService {
  factory ProductionStreamResolutionService({
    required UserCredentials credentials,
    HttpClient? httpClient,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return ProductionStreamResolutionService._(
      credentials,
      httpClient ?? _sharedClient,
      timeout,
    );
  }

  ProductionStreamResolutionService._(
    this._credentials,
    this._client,
    this._timeout,
  );

  static final HttpClient _sharedClient = HttpClient();

  final UserCredentials _credentials;
  final HttpClient _client;
  final Duration _timeout;

  @override
  Future<StreamResolveResponse?> resolve(StreamResolveRequest request) async {
    try {
      final response = await _post(buildResolveUri(), request.toJson()).timeout(
        _timeout,
      );
      if (response is! Map) return null;
      return StreamResolveResponse.fromJson(
        Map<String, Object?>.from(response),
      );
    } on _ResolverHttpException catch (error) {
      if (error.statusCode == HttpStatus.unauthorized ||
          error.statusCode == HttpStatus.forbidden ||
          error.statusCode == HttpStatus.unprocessableEntity) {
        return const StreamResolveResponse(
          mode: StreamResolveMode.unsupported,
          failure: StreamResolveFailure.rejected,
        );
      }
      return null;
    } on Object {
      return null;
    }
  }

  @visibleForTesting
  Uri buildResolveUri() {
    final uri = Uri.parse(_credentials.server.replaceAll(RegExp(r'/+$'), ''));
    final path = uri.path.endsWith('/player_api.php')
        ? uri.path.substring(0, uri.path.length - '/player_api.php'.length)
        : uri.path.replaceAll(RegExp(r'/+$'), '');
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '$path/api/tv/stream/resolve',
    );
  }

  Future<Object?> _post(Uri uri, Map<String, Object?> body) async {
    final request = await _client.postUrl(uri);
    request.followRedirects = false;
    final bytes = utf8.encode(jsonEncode(body));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, _basicAuthorization);
    request
      ..contentLength = bytes.length
      ..add(bytes);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode >= HttpStatus.multipleChoices) {
      throw _ResolverHttpException(response.statusCode);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  String get _basicAuthorization {
    final value = base64Encode(
      utf8.encode('${_credentials.username}:${_credentials.password}'),
    );
    return 'Basic $value';
  }
}

class _ResolverHttpException implements Exception {
  const _ResolverHttpException(this.statusCode);

  final int statusCode;
}
