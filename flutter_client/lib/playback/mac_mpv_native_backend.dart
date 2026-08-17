import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/mpv_native_backend_base.dart';
import 'package:m3u_tv/playback/mpv_native_event.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

// Shared broadcast event stream, same rationale as desktop_libmpv_backend.dart:
// receiveBroadcastStream() must be listened to exactly once and shared across
// instances (each [MacMpvNativeBackend] filters it down to its own [viewId]
// in MpvNativeBackendBase._applyEvent). Do not wrap in .asBroadcastStream()
// -- its pause/resume semantics break resubscription across sequential
// loads/disposes.
Stream<MpvNativeEvent>? _sharedMpvEvents;
Stream<MpvNativeEvent> _mpvEvents(EventChannel channel) {
  return _sharedMpvEvents ??= channel.receiveBroadcastStream().map((raw) {
    final map = Map<String, Object?>.from(raw! as Map<Object?, Object?>);
    return MpvNativeEvent.fromMap(map);
  });
}

int _nextViewId = 0;

/// Native macOS mpv backend rendered through a `FlutterPlatformView`
/// (`AppKitView`) driving `vo=gpu-next`/`gpu-context=moltenvk`/
/// `hwdec=videotoolbox` directly, bypassing the Flutter texture bridge that
/// `MediaKitDesktopAdapter` goes through. Modeled on
/// `macos/Runner/MpvPlayer/MpvPlayerCore.swift`, itself adapted from the
/// open-source Plezy player (github.com/edde746/plezy, GPL-3.0).
///
/// Unlike `DesktopLibmpvBackend`, the native player instance is addressed by
/// a Dart-generated `viewId` (so the `AppKitView` can be created and the
/// native player instance attached to it before `load()` is ever called),
/// not a handle returned from a `load` response.
///
/// Subtitles are rendered natively (mpv's own libass compositing, baked into
/// the `gpu-next`/libplacebo output), so this adapter does not implement
/// `SubtitleControllerProvider`, same as `DesktopLibmpvBackend`.
///
/// Shares its load/play/pause/stop/dispose/event-reduction state machine
/// with `AppleMpvNativeBackend` via `MpvNativeBackendBase` -- the two
/// backends differ only in channel names, capabilities, error codes, and
/// this class's `setVolume`.
class MacMpvNativeBackend extends MpvNativeBackendBase
    implements PlatformViewProvider, MultiviewBackend {
  MacMpvNativeBackend({MethodChannel? channel, EventChannel? eventChannel})
    : super(
        viewId: _nextViewId++,
        channel: channel ?? const MethodChannel(_methodChannelName),
        events: _mpvEvents(
          eventChannel ?? const EventChannel(_eventChannelName),
        ),
      );

  static const String _methodChannelName = 'm3u_tv/mac_mpv';
  static const String _eventChannelName = 'm3u_tv/mac_mpv/events';
  static const String platformViewTypeId = 'm3u_tv/mac_mpv_view';

  @override
  String get platformViewType => platformViewTypeId;

  @override
  Map<String, dynamic>? get platformViewCreationParams => <String, dynamic>{
    'viewId': viewId,
  };

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.macMpvNative;

  @override
  String get loadFailedCode => 'mac-mpv-load-failed';

  @override
  String get defaultErrorCode => 'mac-mpv-error';

  @override
  String get endedBeforeReadyCode => 'mac-mpv-ended-before-ready';

  @override
  Future<void> setVolume(double volume) async {
    // mpv's `volume` property (like media_kit's) is 0-100, not the 0-1 scale
    // [MultiviewBackend.setVolume] uses to match AVPlayer/ExoPlayer.
    await invokeControl('setVolume', <String, Object?>{'volume': volume * 100});
  }
}
