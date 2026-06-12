# Flutter Rewrite Parity Matrix

Wave 1A baseline for the Flutter rewrite. The current `m3u-tv` client is an Expo/React Native TV app plus Electron desktop shell. It authenticates against an m3u-editor backend that exposes Xtream-compatible APIs; the current client does not include a direct M3U playlist parser.

Legend: **C** = current behavior exists, **R** = required for Flutter parity/rewrite, **N/A** = not applicable, **Gap** = not present in current client.

## Feature parity

| Feature | Current RN/Electron behavior | Flutter rewrite parity target | Backend/source mode | Notes |
| --- | --- | --- | --- | --- |
| Live TV | C: category tabs, All Channels, Favorites pseudo-category, list/grid EPG views, lazy EPG loading, D-pad focus, playback route with stream id and EPG id. | R: retain category browsing, favorites, list/grid EPG, focus behavior, live player metadata, and progress heartbeat. | Xtream/m3u-editor now; direct M3U required. | Direct M3U live channels must map `#EXTINF` metadata to channel cards and stream URLs. |
| M3U | Gap: no direct `#EXTM3U`/`#EXTINF` parser in current client; current app connects to m3u-editor/Xtream only. | R: parse valid/malformed M3U, headers/user-agent, grouping, logos, EPG ids/names, stream URLs. | Direct M3U required; Xtream unchanged. | Parser must support `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, stream URL, and custom header/user-agent conventions. |
| Xtream | C: requires auth success plus `m3u_editor` metadata, trims trailing server slash, stores credentials securely, fetches categories/streams/details. | R: preserve auth, API paths, m3u-editor header, categories, stream URL construction, and stale-cache fallback. | Xtream/m3u-editor. | Non-m3u-editor Xtream is rejected by current app. |
| EPG | C: JSON Xtream EPG only; short EPG for current/next, batch/full grid loading, 30-minute freshness, compact AsyncStorage restore. | R: preserve current/next, timeline grid, cache restore, batch fallback; add direct M3U XMLTV/EPG mapping fixtures. | Xtream/m3u-editor now; direct M3U EPG mapping required. | Current app does not download XMLTV. |
| VOD | C: VOD categories/streams/details, posters/backdrops/metadata, resume dialog, stream URL extension with web-safe fallback. | R: preserve details, resume, metadata, posters, direct/native playback and fallback behavior. | Xtream/m3u-editor. | Web rewrites unsupported containers to `.mp4` in URL construction. |
| Series | C: series categories/list/details, season synthesis if missing, episode list, episode progress bars, resume dialog. | R: preserve seasons/episodes, fallback season synthesis, progress/resume, metadata. | Xtream/m3u-editor. | Episode playback passes `seriesId` and `seasonNumber` for progress. |
| Search | C: client-side case-insensitive name search across fetched Live TV, Movies, and Series, with type filter tabs. | R: preserve all/live/vod/series filters and result card navigation; add direct M3U channel search. | Cached/fetched client data. | Search does not call a backend search endpoint. |
| Favorites | C: live-channel favorites only; persisted numeric stream IDs; long-press in Live TV toggles; Home and Live TV show favorites. | R: preserve live favorites and define direct M3U stable channel identity. | Local storage. | No VOD/Series favorites in current client. |
| Continue Watching | C: m3u-editor viewer-scoped progress for VOD/episodes; Home row excludes live; resume/start-over dialogs. | R: preserve viewer-scoped VOD/episode resume and progress update cadence; define local fallback if backend unavailable. | m3u-editor progress API. | Live progress is marked but not shown in Continue Watching. |
| Settings | C: connection form, connected stats, active viewer switching, refresh interval, EPG view mode, manual refresh, clear cache, disconnect. | R: preserve connection/profile/cache settings and TV focus affordances across all platforms. | Local settings + Xtream/m3u-editor. | Refresh interval controls content cache staleness. |
| Subtitles | C: native mpv text track selector; Electron embedded mpv subtitle cycling; HTML5 fallback has no subtitle selector. | R: expose subtitle tracks wherever backend supports direct native/mpv; document unsupported native fallback behavior. | Player backend dependent. | Native uses Off + text tracks; Electron uses `sid`. |
| Audio Tracks | C: native mpv audio selector; Electron embedded mpv audio cycling; HTML5 fallback has no audio selector. | R: expose audio tracks wherever backend supports direct native/mpv; document unsupported native fallback behavior. | Player backend dependent. | Native selector includes Disable; Electron uses `aid`. |

## Platform parity

| Platform | Current support | Flutter rewrite target | Playback backend target | Notes |
| --- | --- | --- | --- | --- |
| Windows | C via Electron web build. | R native Flutter desktop. | direct native/mpv, native fallback, server transcode fallback. | Current Electron uses mpv takeover/external fallback. |
| Linux | C via Electron web build. | R native Flutter desktop. | direct native/mpv, native fallback, server transcode fallback. | Current mpv controller supports X11/Wayland takeover and Flatpak mpv lookup. |
| macOS | C via Electron web build. | R native Flutter desktop. | direct native/mpv, native fallback, server transcode fallback. | Current browser/Safari can direct-play native HLS; Electron can use mpv if installed. |
| Android | C via React Native mobile/native path. | R Flutter Android. | direct native/mpv, native fallback, server transcode fallback. | Current player is `react-native-mpv` native component. |
| Android TV | C primary React Native TV target. | R Flutter Android TV. | direct native/mpv, native fallback, server transcode fallback. | D-pad focus/back behavior is mandatory. |
| iOS | C via React Native native path. | R Flutter iOS. | native fallback, server transcode fallback; mpv only if safe/approved. | Current selector uses ActionSheet on non-TV iOS. |
| tvOS | C primary React Native TV target. | R Flutter tvOS. | native fallback, server transcode fallback; mpv bridge requires risk review. | Prior wisdom notes Apple/tvOS mpv bridge crash risk. |

## Playback backend parity

| Backend | Current behavior | Flutter rewrite expectation | Applies to |
| --- | --- | --- | --- |
| direct native/mpv | Native RN uses `react-native-mpv`; Electron tries mpv takeover with JSON IPC; web browser uses HLS.js/direct HTML5. | Prefer direct native/mpv on desktop/Android where viable; expose progress, pause, seek, buffering, end, audio tracks, subtitle tracks. | Windows, Linux, macOS, Android, Android TV. |
| native fallback | Current web/browser path uses HLS.js for `.m3u8` or direct video element for MP4/WebM; Electron falls back to external player. | Use platform native media stack when mpv is unavailable or unsafe. | macOS, iOS, tvOS, web-like fallback paths. |
| server transcode fallback | Gap in current client UI; inherited wisdom says m3u-editor dev branch is source of truth for transcoding. | Add explicit fallback contract for direct playback failure, success/failure states, and user messaging. | All platforms, especially unsupported codecs/containers. |

## Direct M3U rewrite requirements

The Flutter rewrite must add direct M3U behavior not present in the current client:

- Accept `#EXTM3U` playlists and tolerate malformed entries without crashing.
- Parse `#EXTINF` display names plus attributes: `tvg-id`, `tvg-name`, `tvg-logo`, and `group-title`.
- Treat the following non-comment line after `#EXTINF` as the stream URL.
- Preserve or normalize custom headers/user-agent metadata for playback backends that support them.
- Group channels by `group-title`, with an All Channels view and stable grouping for missing groups.
- Map EPG data by `tvg-id` first, then `tvg-name`/display-name fallback.
