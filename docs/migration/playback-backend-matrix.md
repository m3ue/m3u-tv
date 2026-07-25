# Playback Backend Matrix

This matrix defines the Flutter rewrite playback contract before any native plugin work. UI-facing playback code must depend on `PlayerAdapter` only; backend selection, unsupported-media failure, and server-transcode fallback must happen behind that adapter so widgets do not change when the active backend changes.

## Contract invariants

- `PlayerAdapter` exposes imperative controls: `load`, `play`, `pause`, `seek`, `stop`, `dispose`, `setAudioTrack`, `setSubtitleTrack`, and `setPlaybackSpeed`.
- State and errors flow through `onState` and `onError`; widgets observe those streams rather than native implementation events.
- Unsupported direct playback is represented as an unsupported playback exception and may switch to a server-transcode adapter without changing widget code.
- External player launch is not a normal backend in the Flutter contract. The retired Electron external-player path remains reference-only behavior.
- Capability flags describe guaranteed contract support, not every codec a device might decode opportunistically.

## Platform fallback order

| Platform | Direct native/mpv backend | Native fallback backend | Server transcode fallback | Notes |
| --- | --- | --- | --- | --- |
| Android / Android TV | Android ExoPlayer for common HLS, MPEG-TS, and MP4 streams. | Android MPV fallback for broader containers, advanced codecs, external subtitles, and advanced subtitle formats. | Yes: server-transcoded HLS output when direct/native backends reject unsupported media. | Android TV UI must keep D-pad widgets unchanged while adapter selection changes. |
| tvOS / iOS Apple path | None — MPVKit is not planned. GPL-3.0 is incompatible with App Store distribution for this app, a firm decision rather than a review gate. | AVKit, the permanent primary backend for platform-native HLS/MP4 playback. | Yes: server-transcoded HLS output when AVKit cannot satisfy the source. | AVKit is narrower than MPVKit (no ASS subtitles or arbitrary containers) and that gap is accepted, not planned to be closed via MPVKit. macOS is not part of this path — see the Desktop Flutter row. |
| Desktop Flutter (Linux/Windows) | libmpv direct backend via `DesktopLibmpvBackend`. | No external-player fallback is exposed as a contract backend; future platform-native fallback must get its own capability row before use. | Yes: server-transcoded HLS output when libmpv is unavailable or policy rejects the source. | Retired Electron mpv takeover and external launch are behavior references only. |
| Desktop Flutter (macOS) | media_kit (AVFoundation-backed) via `MediaKitDesktopAdapter`, registered under the `desktopMediaKit` backend key. Not libmpv. | No external-player fallback is exposed as a contract backend. | Yes: server-transcoded HLS output when media_kit cannot satisfy the source. | A native in-process libmpv backend was prototyped and reverted (media_kit already worked correctly); libmpv on macOS is not planned. |
| Server Transcode | N/A. | N/A. | HLS playback URL produced by m3u-editor/server transcode contract. | This backend normalizes playback but does not expose direct stream or embedded-track capabilities. |

## Capability flags by backend

Legend: Yes means guaranteed by the adapter contract for that backend. No means UI must hide/disable or avoid relying on the feature unless a later backend-specific contract expands it.

| Backend | Direct streams | HLS | MPEG-TS | MP4 | Advanced codecs | Audio tracks | Subtitle tracks | External subtitles | Advanced subtitle formats | Speed | Seek | Live seek | Explicit unsupported features |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Android ExoPlayer | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | No | advanced-codecs, external-subtitles, advanced-subtitle-formats, live-seek |
| Android MPV fallback | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | live-seek |
| Apple Media Kit (iOS fallback) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | live-seek |
| Apple AVKit fallback | Yes | Yes | No | Yes | No | Yes | Yes | No | No | Yes | Yes | No | mpeg-ts, advanced-codecs, external-subtitles, advanced-subtitle-formats, live-seek |
| Desktop libmpv (Linux/Windows) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | live-seek |
| Desktop Media Kit (macOS) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | live-seek |
| Server transcode fallback | No | Yes | No | No | No | No | No | No | No | No | Yes | No | direct-streams, mpeg-ts, mp4, advanced-codecs, audio-track-selection, subtitle-track-selection, embedded-subtitles, external-subtitles, advanced-subtitle-formats, playback-speed, live-seek |

## UI transparency requirement

The adapter chosen by playback orchestration may start as a direct native backend and end as server transcode for the same `PlaybackSource`. UI code must not branch on ExoPlayer, MPVKit, libmpv, or server-transcode implementation classes. It may read `PlaybackState.backend` and `PlaybackCapabilities` to label/debug behavior or hide unsupported controls, but control dispatch remains the same `PlayerAdapter` method calls.
