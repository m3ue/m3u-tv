import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/mpv_native_backend_base.dart';
import 'package:m3u_tv/playback/mpv_native_event.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

// Shared broadcast event stream, same rationale as mac_mpv_native_backend.dart
// and apple_mpv_native_backend.dart: receiveBroadcastStream() must be
// listened to exactly once and shared across instances (each
// [AndroidMpvBackend] filters it down to its own [viewId] in
// MpvNativeBackendBase._applyEvent). Do not wrap in .asBroadcastStream() --
// its pause/resume semantics break resubscription across sequential
// loads/disposes.
Stream<MpvNativeEvent>? _sharedMpvEvents;
Stream<MpvNativeEvent> _mpvEvents(EventChannel channel) {
  return _sharedMpvEvents ??= channel.receiveBroadcastStream().map((raw) {
    final map = Map<String, Object?>.from(raw! as Map<Object?, Object?>);
    return MpvNativeEvent.fromMap(map);
  });
}

int _nextViewId = 0;

/// Native Android/Android TV mpv backend rendered through a `FlutterPlatformView`
/// (`AndroidView`) hosting a `SurfaceView` that mpv draws into directly via
/// `vo=gpu-next`/`gpu-context=android`/`hwdec=mediacodec`, bypassing the
/// Flutter texture bridge -- same architecture family as
/// `MacMpvNativeBackend`/`AppleMpvNativeBackend`, modeled on the open-source
/// Plezy player (github.com/edde746/plezy, GPL-3.0), whose Android core uses
/// the same `dev.jdtech.mpv` libmpv bindings this backend's native side
/// (`android/app/src/main/kotlin/dev/sparkison/tv/mpv/MpvPlayerCore.kt`) uses.
///
/// Unlike `MacMpvNativeBackend`/`AppleMpvNativeBackend`, the native
/// `dev.jdtech.mpv.MpvPlayer` this backend wraps is a process-wide singleton
/// (it owns one native mpv handle via static JNI bindings) -- only one
/// `AndroidMpvBackend` instance can be attached at a time. It is therefore
/// only registered as the single-player primary backend in
/// `buildPlaybackOrchestrator` (lib/navigation/app_router.dart), never in
/// `buildMultiviewTilePlayer`; Multiview on Android stays on
/// `AndroidPlaybackAdapter` (ExoPlayer), which already supports several
/// concurrent instances keyed by `playerId`.
///
/// The native player instance is addressed by a Dart-generated `viewId` (so
/// the `AndroidView` can be created and the native player instance attached
/// to it before `load()` is ever called), not a handle returned from a
/// `load` response.
///
/// Subtitles are rendered natively (mpv's own libass compositing), same as
/// `MacMpvNativeBackend`/`AppleMpvNativeBackend`/`DesktopLibmpvBackend`.
///
/// Shares its load/play/pause/stop/dispose/event-reduction state machine
/// with the other native mpv backends via `MpvNativeBackendBase`.
class AndroidMpvBackend extends MpvNativeBackendBase
    implements PlatformViewProvider {
  AndroidMpvBackend({MethodChannel? channel, EventChannel? eventChannel})
    : super(
        viewId: _nextViewId++,
        channel: channel ?? const MethodChannel(_methodChannelName),
        events: _mpvEvents(
          eventChannel ?? const EventChannel(_eventChannelName),
        ),
      );

  static const String _methodChannelName = 'm3u_tv/android_mpv';
  static const String _eventChannelName = 'm3u_tv/android_mpv/events';
  static const String platformViewTypeId = 'm3u_tv/android_mpv_view';

  @override
  String get platformViewType => platformViewTypeId;

  @override
  Map<String, dynamic>? get platformViewCreationParams => <String, dynamic>{
    'viewId': viewId,
  };

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.androidMpv;

  @override
  String get loadFailedCode => 'android-mpv-load-failed';

  @override
  String get defaultErrorCode => 'android-mpv-error';

  @override
  String get endedBeforeReadyCode => 'android-mpv-ended-before-ready';
}
