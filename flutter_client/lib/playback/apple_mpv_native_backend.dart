import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/mpv_native_backend_base.dart';
import 'package:m3u_tv/playback/mpv_native_event.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

// Shared broadcast event stream, same rationale as desktop_libmpv_backend.dart
// and mac_mpv_native_backend.dart: receiveBroadcastStream() must be listened
// to exactly once and shared across instances (each [AppleMpvNativeBackend]
// filters it down to its own [viewId] in MpvNativeBackendBase._applyEvent).
// Do not wrap in .asBroadcastStream() -- its pause/resume semantics break
// resubscription across sequential loads/disposes.
Stream<MpvNativeEvent>? _sharedMpvEvents;
Stream<MpvNativeEvent> _mpvEvents(EventChannel channel) {
  return _sharedMpvEvents ??= channel.receiveBroadcastStream().map((raw) {
    final map = Map<String, Object?>.from(raw! as Map<Object?, Object?>);
    return MpvNativeEvent.fromMap(map);
  });
}

int _nextViewId = 0;

/// Native iOS/tvOS mpv backend rendered through a `FlutterPlatformView`
/// (`UiKitView`) driving `vo=avfoundation`/`hwdec=videotoolbox` directly,
/// rendering to an `AVSampleBufferDisplayLayer` and bypassing the Flutter
/// texture bridge that `MediaKitIosAdapter` goes through. Modeled on
/// `ios/Runner/MpvPlayer/MpvPlayerCore.swift` and
/// `tvos/Runner/MpvPlayer/MpvPlayerCore.swift`, themselves adapted from the
/// open-source Plezy player (github.com/edde746/plezy, GPL-3.0). One shared
/// Dart adapter and channel pair covers both iOS and tvOS, the same
/// convention `AppleAvKitBackend`/`m3u_tv/apple_avkit` already uses for its
/// near-duplicate per-platform native Swift implementations.
///
/// Like `MacMpvNativeBackend`, the native player instance is addressed by a
/// Dart-generated `viewId` so the platform view can be created and attached
/// before `load()` is ever called, and subtitles are rendered natively
/// (mpv's own libass compositing), so this adapter does not implement
/// `SubtitleControllerProvider`.
///
/// Shares its load/play/pause/stop/dispose/event-reduction state machine
/// with `MacMpvNativeBackend` via `MpvNativeBackendBase` -- the two backends
/// differ only in channel names, capabilities, and error codes.
class AppleMpvNativeBackend extends MpvNativeBackendBase
    implements PlatformViewProvider {
  AppleMpvNativeBackend({MethodChannel? channel, EventChannel? eventChannel})
    : super(
        viewId: _nextViewId++,
        channel: channel ?? const MethodChannel(_methodChannelName),
        events: _mpvEvents(
          eventChannel ?? const EventChannel(_eventChannelName),
        ),
      );

  static const String _methodChannelName = 'm3u_tv/apple_mpv';
  static const String _eventChannelName = 'm3u_tv/apple_mpv/events';
  static const String platformViewTypeId = 'm3u_tv/apple_mpv_view';

  @override
  String get platformViewType => platformViewTypeId;

  @override
  Map<String, dynamic>? get platformViewCreationParams => <String, dynamic>{
    'viewId': viewId,
  };

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.appleMpvNative;

  @override
  String get loadFailedCode => 'apple-mpv-load-failed';

  @override
  String get defaultErrorCode => 'apple-mpv-error';

  @override
  String get endedBeforeReadyCode => 'apple-mpv-ended-before-ready';
}
