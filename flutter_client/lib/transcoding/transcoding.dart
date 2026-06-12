enum TranscodeMode {
  direct('direct'),
  server('server'),
  local('local');

  const TranscodeMode(this.value);

  final String value;

  static TranscodeMode fromValue(String value) {
    return TranscodeMode.values.firstWhere(
      (TranscodeMode mode) => mode.value == value,
      orElse: () => throw ArgumentError.value(value, 'value', 'Unknown transcode mode'),
    );
  }
}

enum BroadcastStatus {
  starting('starting'),
  running('running'),
  stopped('stopped'),
  stalled('stalled'),
  failed('failed'),
  cancelled('cancelled');

  const BroadcastStatus(this.value);

  final String value;

  static BroadcastStatus fromValue(String value) {
    return BroadcastStatus.values.firstWhere(
      (BroadcastStatus status) => status.value == value,
      orElse: () => throw ArgumentError.value(value, 'value', 'Unknown broadcast status'),
    );
  }
}

class StreamRequest {
  const StreamRequest({
    required this.url,
    required this.mode,
    this.metadata = const <String, Object?>{},
    this.userAgent,
    this.headers = const <String, String>{},
    this.failoverUrls = const <String>[],
    this.profile,
    this.resolver,
    this.resolverArgs,
    this.cookiesPath,
    this.videoCodec,
    this.audioCodec,
    this.sessionId,
  });

  final String url;
  final TranscodeMode mode;
  final Map<String, Object?> metadata;
  final String? userAgent;
  final Map<String, String> headers;
  final List<String> failoverUrls;
  final String? profile;
  final String? resolver;
  final String? resolverArgs;
  final String? cookiesPath;
  final String? videoCodec;
  final String? audioCodec;
  final String? sessionId;

  Map<String, Object?> toJson() {
    return _withoutNulls(<String, Object?>{
      'url': url,
      'mode': mode.value,
      'metadata': metadata,
      'user_agent': userAgent,
      'headers': headers.isEmpty ? null : headers,
      'failover_urls': failoverUrls.isEmpty ? null : failoverUrls,
      'profile': profile,
      'resolver': resolver,
      'resolver_args': resolverArgs,
      'cookies_path': cookiesPath,
      'video_codec': videoCodec,
      'audio_codec': audioCodec,
      'session_id': sessionId,
    });
  }
}

class TranscodeResponse {
  const TranscodeResponse({
    required this.streamId,
    required this.streamUrl,
    required this.mode,
    required this.status,
    this.sessionId,
    this.errorCode,
    this.message,
  });

  factory TranscodeResponse.fromJson(Map<String, Object?> json) {
    return TranscodeResponse(
      streamId: _requiredString(json, 'stream_id'),
      streamUrl: _requiredString(json, 'stream_url'),
      mode: TranscodeMode.fromValue(_requiredString(json, 'mode')),
      status: _requiredString(json, 'status'),
      sessionId: json['session_id'] as String?,
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
    );
  }

  final String streamId;
  final String streamUrl;
  final TranscodeMode mode;
  final String status;
  final String? sessionId;
  final String? errorCode;
  final String? message;

  Map<String, Object?> toJson() {
    return _withoutNulls(<String, Object?>{
      'stream_id': streamId,
      'stream_url': streamUrl,
      'mode': mode.value,
      'status': status,
      'session_id': sessionId,
      'error_code': errorCode,
      'message': message,
    });
  }
}

class BroadcastSession {
  const BroadcastSession({
    required this.networkId,
    required this.status,
    this.ffmpegPid,
    this.playlistUrl,
    this.finalSegmentNumber,
    this.transcodeSessionId,
    this.errorCode,
    this.message,
  });

  factory BroadcastSession.fromJson(Map<String, Object?> json) {
    return BroadcastSession(
      networkId: _requiredString(json, 'network_id'),
      status: BroadcastStatus.fromValue(_requiredString(json, 'status')),
      ffmpegPid: json['ffmpeg_pid'] as int?,
      playlistUrl: json['playlist_url'] as String?,
      finalSegmentNumber: json['final_segment_number'] as int?,
      transcodeSessionId: json['transcode_session_id'] as String?,
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
    );
  }

  final String networkId;
  final BroadcastStatus status;
  final int? ffmpegPid;
  final String? playlistUrl;
  final int? finalSegmentNumber;
  final String? transcodeSessionId;
  final String? errorCode;
  final String? message;

  Map<String, Object?> toJson() {
    return _withoutNulls(<String, Object?>{
      'network_id': networkId,
      'status': status.value,
      'ffmpeg_pid': ffmpegPid,
      'playlist_url': playlistUrl,
      'final_segment_number': finalSegmentNumber,
      'transcode_session_id': transcodeSessionId,
      'error_code': errorCode,
      'message': message,
    });
  }
}

Map<String, Object?> _withoutNulls(Map<String, Object?> value) {
  return Map<String, Object?>.fromEntries(
    value.entries.where((MapEntry<String, Object?> entry) => entry.value != null),
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }

  throw FormatException('Missing required string field: $key');
}
