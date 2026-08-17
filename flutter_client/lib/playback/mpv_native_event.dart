import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

/// The mpv event kinds emitted by every native mpv `MpvPlayerCore.swift`
/// (macOS/iOS/tvOS) over its `dart:async` `EventChannel` -- the wire schema
/// is identical across all three platforms, so one shared type covers all
/// of them. See `[platform]/Runner/MpvPlayer/MpvPlayerCore.swift`'s `emit`.
enum MpvNativeEventKind {
  startFile,
  fileLoaded,
  playbackRestart,
  videoReconfig,
  endFile,
  stop,
  quit,
  error,
  shutdown,
  unknown,
}

MpvNativeEventKind _kindFromString(String? value) {
  return switch (value) {
    'START_FILE' => MpvNativeEventKind.startFile,
    'FILE_LOADED' => MpvNativeEventKind.fileLoaded,
    'PLAYBACK_RESTART' => MpvNativeEventKind.playbackRestart,
    'VIDEO_RECONFIG' => MpvNativeEventKind.videoReconfig,
    'END_FILE' => MpvNativeEventKind.endFile,
    'STOP' => MpvNativeEventKind.stop,
    'QUIT' => MpvNativeEventKind.quit,
    'ERROR' => MpvNativeEventKind.error,
    'SHUTDOWN' => MpvNativeEventKind.shutdown,
    _ => MpvNativeEventKind.unknown,
  };
}

double? _asPositiveDouble(Object? value) {
  if (value is num && value > 0) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

Duration? _asPositiveDuration(Object? value) {
  if (value is! num || value <= 0) return null;
  return Duration(milliseconds: value.round());
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String? _selectedTrackId(Object? value) {
  final id = _nonEmptyString(value);
  return id == null || id.toLowerCase() == 'no' ? null : id;
}

List<PlaybackTrack>? _tracksFromValue(Object? value) {
  if (value is! List<Object?>) return null;
  final tracks = <PlaybackTrack>[];
  for (final item in value) {
    if (item is! Map<Object?, Object?>) continue;
    final id = _nonEmptyString(item['id']);
    if (id == null) continue;
    final language = _nonEmptyString(item['language']);
    final label = _nonEmptyString(item['label']) ?? language ?? id;
    tracks.add(PlaybackTrack(id: id, label: label, language: language));
  }
  return tracks;
}

/// One decoded event from a native mpv `EventChannel` payload. Shared
/// between `MacMpvNativeBackend` and `AppleMpvNativeBackend` -- the wire
/// schema each native `MpvPlayerCore.swift`'s `emit`/`emitError` produces
/// is identical across macOS/iOS/tvOS.
class MpvNativeEvent {
  const MpvNativeEvent({
    required this.viewId,
    required this.sequence,
    required this.kind,
    this.position,
    this.duration,
    this.paused = false,
    this.buffering = false,
    this.eof = false,
    this.videoAspectRatio,
    this.speed,
    this.aid,
    this.sid,
    this.hasAid = false,
    this.hasSid = false,
    this.audioTracks,
    this.subtitleTracks,
    this.message,
    this.code,
    this.recoverable = false,
  });

  factory MpvNativeEvent.fromMap(Map<String, Object?> map) {
    return MpvNativeEvent(
      viewId: (map['viewId'] as num?)?.toInt() ?? 0,
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      kind: _kindFromString(map['kind'] as String?),
      position: map['positionMs'] is num
          ? Duration(milliseconds: (map['positionMs']! as num).round())
          : Duration.zero,
      duration: _asPositiveDuration(map['durationMs']),
      paused: map['paused'] == true,
      buffering: map['buffering'] == true,
      eof: map['eof'] == true,
      videoAspectRatio: playbackAspectRatioFromValues(
        aspectRatio:
            map['videoAspectRatio'] ??
            map['displayAspectRatio'] ??
            map['aspectRatio'],
        width: map['videoWidth'] ?? map['width'],
        height: map['videoHeight'] ?? map['height'],
      ),
      speed: _asPositiveDouble(map['speed']),
      aid: _selectedTrackId(map['aid']),
      sid: _selectedTrackId(map['sid']),
      hasAid: map.containsKey('aid'),
      hasSid: map.containsKey('sid'),
      audioTracks: _tracksFromValue(map['audioTracks']),
      subtitleTracks: _tracksFromValue(map['subtitleTracks']),
      message: map['message'] as String?,
      code: map['code'] as String?,
      recoverable: map['recoverable'] == true,
    );
  }

  final int viewId;
  final int sequence;
  final MpvNativeEventKind kind;
  final Duration? position;
  final Duration? duration;
  final bool paused;
  final bool buffering;
  final bool eof;
  final double? videoAspectRatio;
  final double? speed;
  final String? aid;
  final String? sid;
  final bool hasAid;
  final bool hasSid;
  final List<PlaybackTrack>? audioTracks;
  final List<PlaybackTrack>? subtitleTracks;
  final String? message;
  final String? code;
  final bool recoverable;
}

/// Reduces a [MpvNativeEvent] onto a [PlaybackState]. Shared between
/// `MacMpvNativeBackend` and `AppleMpvNativeBackend`; `backend` selects
/// which [PlaybackBackend] the resulting state reports.
class MpvNativeEventReducer {
  const MpvNativeEventReducer._();

  static PlaybackState reduce(
    PlaybackState current,
    MpvNativeEvent event,
    PlaybackSource source, {
    required PlaybackBackend backend,
  }) {
    switch (event.kind) {
      case MpvNativeEventKind.startFile:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.loading,
          source: source,
          position: source.startPosition,
        );
      case MpvNativeEventKind.fileLoaded:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.ready,
          source: source,
          position: event.position ?? source.startPosition,
          duration: event.duration,
          videoAspectRatio: event.videoAspectRatio,
          playbackSpeed: event.speed,
          audioTracks: event.audioTracks ?? const <PlaybackTrack>[],
          subtitleTracks: event.subtitleTracks ?? const <PlaybackTrack>[],
          selectedAudioTrackId: event.hasAid ? event.aid : null,
          selectedSubtitleTrackId: event.hasSid ? event.sid : null,
          isAudioTrackSelectionKnown: event.hasAid,
          isSubtitleTrackSelectionKnown: event.hasSid,
        );
      case MpvNativeEventKind.playbackRestart:
        final status = event.paused
            ? PlaybackStatus.paused
            : event.buffering
            ? PlaybackStatus.buffering
            : PlaybackStatus.playing;
        return current.copyWith(
          backend: backend,
          status: status,
          position: event.position ?? current.position,
          duration: event.duration ?? current.duration,
          videoAspectRatio: event.videoAspectRatio ?? current.videoAspectRatio,
          playbackSpeed: event.speed ?? current.playbackSpeed,
          audioTracks: event.audioTracks ?? current.audioTracks,
          subtitleTracks: event.subtitleTracks ?? current.subtitleTracks,
          selectedAudioTrackId: event.hasAid
              ? event.aid
              : current.selectedAudioTrackId,
          selectedSubtitleTrackId: event.hasSid
              ? event.sid
              : current.selectedSubtitleTrackId,
          isAudioTrackSelectionKnown:
              event.hasAid || current.isAudioTrackSelectionKnown,
          isSubtitleTrackSelectionKnown:
              event.hasSid || current.isSubtitleTrackSelectionKnown,
        );
      case MpvNativeEventKind.videoReconfig:
        return current.copyWith(
          backend: backend,
          videoAspectRatio: event.videoAspectRatio ?? current.videoAspectRatio,
        );
      case MpvNativeEventKind.endFile:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.completed,
        );
      case MpvNativeEventKind.stop:
      case MpvNativeEventKind.quit:
      case MpvNativeEventKind.shutdown:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.stopped,
        );
      case MpvNativeEventKind.error:
        // Errors are emitted as PlaybackError; state is left unchanged.
        return current;
      case MpvNativeEventKind.unknown:
        return current;
    }
  }
}
