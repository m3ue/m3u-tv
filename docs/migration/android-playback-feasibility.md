# Android Playback Feasibility

## Decision

The Flutter rewrite should use an Android playback adapter that tries ExoPlayer first, falls back to embedded libmpv/MPV for direct playback gaps, and only then asks the m3u-editor server for a transcoded stream. It must not launch external player intents because Android TV playback needs in-app focus, resume, EPG, audio-track, and subtitle control.

## Backend order

1. **Android ExoPlayer** is the first backend for normal HLS, MPEG-TS, and MP4 streams. Capability detection must be per device rather than assumed globally: H.264, H.265/HEVC, and AV1 depend on MediaCodec hardware support, and AC3/DTS depend on passthrough or decoder availability.
2. **Android MPV/libmpv** is the direct-play fallback for unsupported codecs, advanced subtitle formats, black-screen reports, and MediaCodec decoder failures. The existing React Native Android reference initializes libmpv with an Android GPU surface, `mediacodec-copy`, AudioTrack output, cache/network settings, and track observers; the Flutter adapter should preserve that shape when native binding work begins.
3. **Server transcode** is the final fallback when ExoPlayer cannot handle the stream and MPV is not available or cannot recover. This keeps unsupported provider fixtures playable without assuming every Android TV box can decode every advertised format.

## Codec and feature matrix

| Feature | ExoPlayer first backend | MPV fallback | Server transcode fallback |
|---|---|---|---|
| H.264 | Direct when MediaCodec reports support | Direct | Transcoded output |
| H.265/HEVC | Direct only on supported devices | Direct fallback | Transcoded output |
| AV1 | Direct only on supported devices | Direct fallback | Transcoded output |
| AC3 | Direct/passthrough only when reported | Direct fallback | Transcoded audio |
| DTS | Do not assume support | Direct fallback | Transcoded audio |
| Subtitles | Embedded/basic tracks | Embedded, external, advanced formats | Burned or selected server-side |
| Audio tracks | ExoPlayer track selection | MPV `aid` selection | Server-selected output |

## Test coverage added

- `flutter_client/test/playback/android_backend_fallback_test.dart` pins the Android capability report for H.264, H.265, AV1, AC3, DTS, subtitles, and audio tracks.
- The unsupported HEVC/DTS fixture proves MPV fallback when libmpv is available.
- Decoder failure and black-screen metadata force MPV even when the nominal codec is supported.
- A no-MPV probe proves server transcode fallback for unsupported audio.
- `AndroidTvPlayerOverlay` uses Flutter focus/key handling for D-pad select, play/pause, arrow focus movement, and back dismissal. Production handling accepts Android `goBack`; tests use `escape` because Flutter's widget test simulator cannot synthesize the Android TV back key directly.

## Licensing boundary

Plezy-style ExoPlayer plus MPV fallback is used as an architectural reference only. Do not copy GPL code into this project. Keep implementation behind the Flutter playback adapter contract and native bindings owned by this repository.
