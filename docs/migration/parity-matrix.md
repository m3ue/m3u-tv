# Flutter Implementation Status

The React Native / Electron app has been fully removed. The Flutter app at `flutter_client/` is the only active TV frontend. This matrix tracks what is implemented, what remains pending, and what is gated/blocked.

Legend: **Done** = implemented in Flutter, **Partial** = partially implemented or player-dependent, **Gap** = not yet implemented, **Gated** = implementation complete but release gated on signing/platform work, **Blocked** = dependency missing (e.g., no Flutter tvOS embedder).

## Feature status

| Feature | Flutter status | Backend/source mode | Notes |
| --- | --- | --- | --- |
| Live TV | Done: category tabs, All Channels, Favorites pseudo-category, D-pad focus, live player with stream id and EPG id. | Xtream/m3u-editor. | Direct M3U live channel support is a future gap (see M3U row). |
| M3U | Gap: no direct `#EXTM3U`/`#EXTINF` parser; app connects to m3u-editor/Xtream only. | Direct M3U required for this feature. | Was also a gap in the RN app. Parser must support `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, stream URL, and custom header/user-agent conventions. |
| Xtream | Done: auth requiring `m3u_editor` metadata, trimmed server URL, secure credential storage, categories/streams/details fetched. | Xtream/m3u-editor. | Non-m3u-editor Xtream backends are rejected by design. |
| EPG | Done: JSON Xtream EPG via `get_epg_batch`; current/next and full timeline grid; in-memory cache; batch JSONL loading per EPG source. | Xtream/m3u-editor. | No XMLTV download. Direct M3U EPG mapping is a future gap. |
| VOD | Done: VOD categories/streams/details, posters/backdrops, resume dialog, stream URL construction. | Xtream/m3u-editor. | |
| Series | Done: series categories/list/details, season synthesis when missing, episode list, progress bars, resume dialog. | Xtream/m3u-editor. | |
| Search | Done: client-side case-insensitive name search across Live TV/Movies/Series with type filter tabs. | Cached/fetched client data. | Search does not call a backend search endpoint. |
| Favorites | Done: live-channel favorites persisted locally; toggle in Live TV; Home and Live TV rows. | Local storage. | No VOD/Series favorites yet. |
| Continue Watching | Done: viewer-scoped VOD/episode resume via m3u-editor progress API; Home row; resume/start-over dialogs. | m3u-editor progress API. | Live progress is marked but not shown in Continue Watching. |
| Settings | Done: connection form with connecting interstitial, connected stats, viewer management dialog (switch/add), EPG refresh interval chips, cache clear, disconnect. | Local settings + Xtream/m3u-editor. | Auto-navigates to Home on successful connection. |
| Subtitles | Partial: ExoPlayer handles embedded/basic tracks on Android. Advanced subtitle formats require MPV fallback (gated). | Player backend dependent. | No subtitle selector UI implemented yet. |
| Audio Tracks | Partial: ExoPlayer track selection on Android. MPV `aid` selection for advanced cases (gated). | Player backend dependent. | Track selector UI pending. |

## Platform status

| Platform | Status | Playback backend | Notes |
| --- | --- | --- | --- |
| Android TV | Active primary target. D-pad navigation, back handling, leanback launcher metadata all implemented. | ExoPlayer first, server transcode fallback. MPV future-gated. | Physical Android TV hardware QA and signed release artifact required before production release. |
| Android phone/tablet | Supported. | Same as Android TV. | Play Store distribution gated on signed AAB, Play Console metadata, and physical device QA. |
| tvOS | Blocked/Gated. No official `flutter build tvos` command. Custom embedder, plugin audit, Siri Remote input bridge, and AVKit playback proof required. | AVKit/AVPlayer once embedder exists. | Does not block Android release track. |
| iOS | Non-blocking/Gated. Flutter iOS project generation works; App Store readiness not claimed. | AVKit/AVPlayer safe default. MPVKit gated by GPL/licensing review. | Does not block Android release track. |
| macOS | Non-blocking/Gated. Flutter macOS project generation works; signing and notarization not proven. | AVKit/AVPlayer safe default. libmpv gated. | Does not block Android release track. |
| Linux desktop | Active (custom backend). `flutter build linux` passes, in-process C++ libmpv path is wired in the orchestrator (see `desktop-libmpv-feasibility.md`). | In-process libmpv via `DesktopLibmpvBackend`; server transcode fallback. | Loads `libmpv.so.2` from the system package at runtime; not yet bundled for portable AppImage/snap/flatpak. Subtitle overlay is not exposed by the custom backend. See `desktop-libmpv-feasibility.md` for current status and known issues. |
| Windows desktop | Active (custom backend). In-process libmpv path is wired in the orchestrator (mirrors Linux). | In-process libmpv via `DesktopLibmpvBackend`; server transcode fallback. | Requires a Windows runner to build and sign; codec/legal review for distributed mpv/FFmpeg DLLs is still outstanding. |

## Playback backend status

| Backend | Status | Applies to |
| --- | --- | --- |
| ExoPlayer (Media3) | Active default for Android/Android TV. Handles H.264, H.265, AV1, AC3 (passthrough), HLS, MPEG-TS, MP4. | Android, Android TV. |
| MPV/libmpv Android | Future-gated fallback for unsupported codecs, advanced subtitles, and MediaCodec failures. | Android, Android TV. |
| AVKit/AVPlayer | Safe default for all Apple platforms. Required for App Store compliance. | iOS, iPadOS, macOS, tvOS (once embedder exists). |
| MPVKit/libmpv Apple | Gated by GPL/LGPL licensing, App Store policy, crash/runtime review, and native dependency review. | macOS, iOS (future). tvOS too risky until embedder is proven. |
| libmpv desktop | Gated by Linux/Windows SDK and runtime packaging work. | Linux, Windows. |
| Server transcode | Final fallback for all platforms when direct playback fails. Contract defined in `m3u-editor-transcoding-contract.md`. | All platforms. |

## Direct M3U requirements (pending)

Direct M3U support is not present in the Flutter app (it was also absent from the RN app). When implemented it must:

- Accept `#EXTM3U` playlists and tolerate malformed entries without crashing.
- Parse `#EXTINF` display names plus attributes: `tvg-id`, `tvg-name`, `tvg-logo`, and `group-title`.
- Treat the following non-comment line after `#EXTINF` as the stream URL.
- Preserve or normalize custom headers/user-agent metadata for playback backends that support them.
- Group channels by `group-title`, with an All Channels view and stable grouping for missing groups.
- Map EPG data by `tvg-id` first, then `tvg-name`/display-name fallback.
