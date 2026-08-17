# Playback Backend Matrix

> **Status update**: the Apple-path rows below ("MPVKit is not planned...")
> predate the project's relicense to GPL-3.0 (repository root `LICENSE`) and
> are now inaccurate. Native mpv (`edde746/MPVKit`, modeled on
> [Plezy](https://github.com/edde746/plezy)) is registered as the **primary**
> backend on tvOS, iOS, and macOS today (`PlaybackBackend.appleMpvNative` /
> `PlaybackBackend.macMpvNative`, see `lib/navigation/app_router.dart`), with
> AVKit demoted to an automatic fallback rather than the primary path.
> `media_kit` (`MediaKitIosAdapter`/`MediaKitDesktopAdapter`) has been
> removed from the main playback fallback chain entirely on iOS and macOS --
> it remains only as the macOS Multiview backend (see the Desktop Flutter
> (macOS) row below for a known regression there). This matrix has been
> updated to reflect that registration and current capability flags.
> **Working status is a separate axis from registration**: native mpv
> playback is confirmed fully working (video, audio, subtitles, track
> switching, seeking, clean teardown) on macOS, iOS, and tvOS. tvOS has one
> known open cosmetic bug (the playback overlay renders "boxed in", smaller
> than the video behind it). See `/MPV_MIGRATION_STATUS.md` at the repo root
> for current status and debugging history, and
> `apple-playback-store-feasibility.md`'s status update for the licensing
> change that unblocked this.

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
| tvOS / iOS Apple path | Native mpv via `PlaybackBackend.appleMpvNative` (`edde746/MPVKit`, `vo=avfoundation` + `hwdec=videotoolbox`, modeled on Plezy). Registered as primary on both iOS and tvOS. `AppleAvKitBackend` (`appleAvKit` backend, iOS + tvOS) is the only automatic fallback if the native mpv backend throws a recoverable `PlaybackException`; `MediaKitIosAdapter` has been removed from the adapter registration entirely. | Yes: server-transcoded HLS output when no native/fallback backend can satisfy the source. | Native mpv is the primary path and is confirmed fully working on both iOS and tvOS (video, audio, no crash on back navigation), not "not planned" as an earlier revision of this doc stated; that framing predated the project's GPL-3.0 relicense, which removed the App Store/GPL blocker. tvOS has one known open cosmetic bug: the playback overlay renders "boxed in" relative to the video. See `/MPV_MIGRATION_STATUS.md`. macOS is not part of this path -- see the Desktop Flutter row. |
| Desktop Flutter (Linux/Windows) | libmpv direct backend via `DesktopLibmpvBackend`. | No external-player fallback is exposed as a contract backend; future platform-native fallback must get its own capability row before use. | Yes: server-transcoded HLS output when libmpv is unavailable or policy rejects the source. | Retired Electron mpv takeover and external launch are behavior references only. |
| Desktop Flutter (macOS) | Native mpv via `PlaybackBackend.macMpvNative` (`edde746/MPVKit`, `vo=gpu-next` + `gpu-context=moltenvk` + `hwdec=videotoolbox`, modeled on Plezy), registered as primary. | None for main playback -- `MediaKitDesktopAdapter` was removed as a fallback in `buildPlaybackOrchestrator()`; there is currently no automatic fallback on macOS if native mpv throws. | Yes: server-transcoded HLS output when native mpv rejects the source (no automatic media_kit fallback in between). | Native mpv is confirmed fully working on macOS (video, audio, subtitles, track switching, seeking, clean back-navigation teardown). `media_kit`/`MediaKitDesktopAdapter` is still used, but only for the separate macOS Multiview surface (`buildMultiviewTilePlayer()`), which is a known regression: it still hard-codes `MediaKitDesktopAdapter`, and since `media_kit_libs_macos_video` was removed from `pubspec.yaml`, `media_kit_video` no longer has a vendored native library to render with on macOS, so Multiview is likely broken there until `MacMpvNativeBackend` gains multi-instance/`playerId` support or another replacement is chosen. Not yet tested or fixed. |
| Server Transcode | N/A. | N/A. | HLS playback URL produced by m3u-editor/server transcode contract. | This backend normalizes playback but does not expose direct stream or embedded-track capabilities. |

## Capability flags by backend

Legend: Yes means guaranteed by the adapter contract for that backend. No means UI must hide/disable or avoid relying on the feature unless a later backend-specific contract expands it.

| Backend | Direct streams | HLS | MPEG-TS | MP4 | Advanced codecs | Audio tracks | Subtitle tracks | External subtitles | Advanced subtitle formats | Speed | Seek | Live seek | Explicit unsupported features |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Android ExoPlayer | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | No | advanced-codecs, external-subtitles, advanced-subtitle-formats, live-seek |
| Android MPV fallback | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | live-seek |
| Apple native mpv (`appleMpvNative`, primary on iOS/tvOS) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | Yes | Yes | Yes | No | external-subtitles, live-seek |
| Apple AVKit fallback | Yes | Yes | No | Yes | No | Yes | Yes | No | No | Yes | Yes | No | mpeg-ts, advanced-codecs, external-subtitles, advanced-subtitle-formats, live-seek |
| Desktop libmpv (Linux/Windows) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | live-seek |
| macOS native mpv (`macMpvNative`, primary on macOS) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | Yes | Yes | Yes | No | external-subtitles, live-seek |
| Desktop Media Kit (macOS Multiview only, not main playback) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | live-seek -- likely broken in practice, see Multiview regression note above |
| Server transcode fallback | No | Yes | No | No | No | No | No | No | No | No | Yes | No | direct-streams, mpeg-ts, mp4, advanced-codecs, audio-track-selection, subtitle-track-selection, embedded-subtitles, external-subtitles, advanced-subtitle-formats, playback-speed, live-seek |

## UI transparency requirement

The adapter chosen by playback orchestration may start as a direct native backend and end as server transcode for the same `PlaybackSource`. UI code must not branch on ExoPlayer, MPVKit, libmpv, or server-transcode implementation classes. It may read `PlaybackState.backend` and `PlaybackCapabilities` to label/debug behavior or hide unsupported controls, but control dispatch remains the same `PlayerAdapter` method calls.
