import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/playback/web_video_backend_stub.dart'
    if (dart.library.js_interop) 'web_video_backend_web.dart'
    as impl;

/// Builds the web platform's primary playback backend (a browser `<video>`
/// element driven by hls.js/mpegts.js/native playback -- see
/// `PlaybackCapabilities.webVideo`). Only ever constructed when running on
/// `kIsWeb` (`buildPlaybackOrchestrator` in `app_router.dart`), so the stub
/// branch's `UnsupportedError` is unreachable in practice.
PlayerAdapter createWebVideoBackend() => impl.createWebVideoBackend();
