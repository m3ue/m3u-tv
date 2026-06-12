# Current Behavior Source References

This document links each parity row to current source references. Line numbers reflect the Wave 1A source read.

## Live TV

- API: `src/services/XtreamService.ts:136-154` fetches live categories/streams and builds `/live/{username}/{password}/{streamId}.m3u8` URLs.
- State/cache: `src/context/XtreamContext.tsx:267-301` reads live stream cache, serves stale cache during refresh/failure, and supports forced refresh.
- Screen: `src/screens/LiveTVScreen.tsx:58-68` loads persisted EPG view mode, favorites, and last category; `src/screens/LiveTVScreen.tsx:187-245` handles favorites filtering and list/grid mode persistence; `src/screens/LiveTVScreen.tsx:246-258` navigates to Player with stream URL, stream id, and EPG channel id; `src/screens/LiveTVScreen.tsx:373-438` renders category bar and list/grid content.
- EPG in live list: `src/screens/LiveTVScreen.tsx:70-185` lazy-loads current/next EPG for visible channels and refreshes progress every 30 seconds.

## M3U

- Current client gap: repo search for `#EXTM3U`, `#EXTINF`, `tvg-id`, and `group-title` found no direct playlist parser in `src/`; current source is Xtream/m3u-editor API based.
- Closest current behavior: `src/types/xtream.ts:86-102` models live channels with `epg_channel_id`, `stream_icon`, `category_id`, and `direct_source`; `src/services/XtreamService.ts:402-414` transforms live streams into UI content items.
- Flutter rewrite must add direct M3U parsing for `#EXTM3U`, `#EXTINF`, `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, stream URL, custom headers/user-agent, malformed entries, grouping, and EPG mapping.

## Xtream

- Credentials/API URL: `src/services/XtreamService.ts:36-78` stores trimmed server credentials and constructs `player_api.php` URLs.
- Client headers/auth: `src/services/XtreamService.ts:88-134` sends `Accept: application/json` and `X-M3UE-Client: m3u-tv`, with auth always identifying as m3u-tv.
- Connect flow: `src/context/XtreamContext.tsx:84-156` sets credentials, requires `user_info.auth === 1`, rejects non-m3u-editor backends, saves credentials, fetches categories, caches them, and starts background EPG restore/load.
- Saved credentials: `src/context/XtreamContext.tsx:178-239` restores secure credentials, uses cached categories immediately, then silently reauthenticates and refreshes stale categories.

## EPG

- Strategy: `src/services/EpgService.ts:51-61` documents JSON Xtream-only EPG: short EPG, batch endpoint, full grid data, in-memory TTL, AsyncStorage restore, no XMLTV download.
- Current/next: `src/services/EpgService.ts:89-114` fetches `get_short_epg(streamId, 4)` on cache miss; `src/services/EpgService.ts:206-234` computes current programme, progress, and next title.
- Batch/full grid: `src/services/EpgService.ts:124-184` batches current/next and full programmes in chunks of 50.
- Xtream batch fallback: `src/services/XtreamService.ts:223-338` tries m3u-editor `get_epg_batch` for yesterday+today, deduplicates by `start_timestamp`, and falls back to individual `get_short_epg`/`get_simple_data_table` chunks.
- Cache: `src/services/EpgService.ts:22-24`, `src/services/EpgService.ts:290-344` use cache key `m3ue_epg_v7`, 30-minute freshness, and one-hour restore validity.

## VOD

- API/URLs: `src/services/XtreamService.ts:156-180` fetches VOD categories/streams/info and builds `/movie/...` URLs; `src/services/XtreamService.ts:23-30` rewrites unsupported web container extensions to `mp4`.
- Cache: `src/context/XtreamContext.tsx:303-337` caches VOD streams with stale refresh/fallback; `src/context/XtreamContext.tsx:375-394` caches VOD details and falls back to cached details on failure.
- Details/resume: `src/screens/MovieDetailsScreen.tsx:31-43` loads details; `src/screens/MovieDetailsScreen.tsx:45-75` loads m3u-editor progress and opens resume dialog for positions over 30 seconds; `src/screens/MovieDetailsScreen.tsx:55-67` navigates to Player with `startPosition`.
- Home row: `src/screens/HomeScreen.tsx:46-66` loads VOD streams and fetches category-specific VOD if the all-VOD response is empty.

## Series

- API/URLs: `src/services/XtreamService.ts:182-206` fetches series categories/list/info and builds `/series/...` episode URLs.
- Cache: `src/context/XtreamContext.tsx:339-373` caches series lists; `src/context/XtreamContext.tsx:396-415` caches series info.
- Details: `src/screens/SeriesDetailsScreen.tsx:65-89` loads series info and synthesizes seasons from episode keys when seasons are missing.
- Episodes/progress: `src/screens/SeriesDetailsScreen.tsx:91-128` loads series progress, opens resume dialog for incomplete episodes over 30 seconds, and navigates to Player with episode metadata.
- UI: `src/screens/SeriesDetailsScreen.tsx:179-274` renders season and episode focus columns with progress bars.

## Search

- Search logic: `src/screens/SearchScreen.tsx:70-120` trims query, lowercases it, fetches selected content types, and performs client-side `name.includes()` matching.
- Filters/results: `src/screens/SearchScreen.tsx:23-35` defines All/Live TV/Movies/Series filters; `src/screens/SearchScreen.tsx:122-144` renders typed cards and stable keys; `src/screens/SearchScreen.tsx:204-241` handles filter tabs and result counts.
- Not configured state: `src/screens/SearchScreen.tsx:146-152` prompts the user to connect in Settings.

## Favorites

- Storage: `src/services/FavoritesService.ts:3-21` stores live favorite IDs under `m3ue_favorites`; corrupt/unavailable storage resets to empty.
- Toggle/read: `src/services/FavoritesService.ts:24-49` toggles numeric stream IDs and persists them.
- Last category: `src/services/FavoritesService.ts:51-66` stores the last selected live category under `m3ue_last_category`.
- Live TV usage: `src/screens/LiveTVScreen.tsx:187-195` toggles favorites via long press and filters the Favorites category; `src/screens/LiveTVScreen.tsx:394-397` injects `★ Favorites` after All Channels.
- Home usage: `src/screens/HomeScreen.tsx:62-65` loads favorite live streams; `src/screens/HomeScreen.tsx:210-231` renders a Favorites row.

## Continue Watching

- Viewer context: `src/context/ViewerContext.tsx:91-137` wraps m3u-editor progress APIs for get/update/series/recently watched using the active viewer.
- Xtream service: `src/services/XtreamService.ts:351-400` implements progress endpoints: `get_progress`, `update_progress`, `get_series_progress`, and `get_recently_watched`.
- Home row: `src/screens/HomeScreen.tsx:40-44` loads recently watched for active m3u-editor viewers; `src/screens/HomeScreen.tsx:68-110` resolves VOD/series rows and navigates with resume position; `src/screens/HomeScreen.tsx:159-208` renders Continue Watching excluding live progress.
- Player updates: `src/screens/PlayerScreen.native.tsx:170-203` and `src/screens/PlayerScreen.web.tsx:477-510` update progress every 10 seconds for VOD/episodes, write final position on unmount, and mark live once.

## Settings

- Connection form: `src/screens/SettingsScreen.tsx:115-125` validates server/username/password and calls connect; `src/screens/SettingsScreen.tsx:353-430` renders the form.
- Connected status: `src/screens/SettingsScreen.tsx:131-209` shows connected status, username, expiry, max/active connections, and category counts.
- Viewer switching: `src/context/ViewerContext.tsx:36-75` loads viewers, defaults to admin/first viewer, persists active viewer; `src/screens/SettingsScreen.tsx:210-234` shows active viewer and Switch Viewer action.
- Cache/settings: `src/services/CacheService.ts:18-21` defaults to 60-minute refresh and list EPG view; `src/screens/SettingsScreen.tsx:74-100` loads/saves refresh interval and EPG view mode and clears cache; `src/screens/SettingsScreen.tsx:236-337` renders refresh interval, EPG view mode, manual refresh, and clear cache.
- Disconnect: `src/context/XtreamContext.tsx:158-176` deletes credentials, clears cache, resets state; `src/screens/SettingsScreen.tsx:127-129` confirms disconnect.

## Subtitles

- Native mpv: `src/screens/PlayerScreen.native.tsx:132-135` stores text tracks and selected text track; `src/screens/PlayerScreen.native.tsx:336-352` opens a subtitle selector with Off + tracks and calls `setSubtitleTrack`; `src/screens/PlayerScreen.native.tsx:410-424` updates tracks from mpv events; `src/screens/PlayerScreen.native.tsx:754-771` renders the subtitle control.
- Electron/mpv legacy reference: `src/screens/PlayerScreen.web.tsx:60-64` stores embedded mpv text track state; `src/screens/PlayerScreen.web.tsx:386-392` receives text tracks; `src/screens/PlayerScreen.web.tsx:699-720` cycles subtitles; `legacy/electron-reference/mpvController.js:278-285` maps mpv sub tracks; `legacy/electron-reference/mpvController.js:342-344` sets `sid` to track id or `no`.
- Browser fallback gap: `src/screens/PlayerScreen.web.tsx:722-741` only exposes fullscreen for non-embedded HTML5 playback; no subtitle selector is wired there.

## Audio Tracks

- Native mpv: `src/screens/PlayerScreen.native.tsx:132-135` stores audio tracks and selected audio track; `src/screens/PlayerScreen.native.tsx:318-334` opens an audio selector with Disable + tracks and calls `setAudioTrack`; `src/screens/PlayerScreen.native.tsx:362-370` loads tracks; `src/screens/PlayerScreen.native.tsx:735-752` renders the audio control.
- Electron/mpv legacy reference: `src/screens/PlayerScreen.web.tsx:58-64` stores embedded mpv audio state; `src/screens/PlayerScreen.web.tsx:386-392` receives audio tracks; `src/screens/PlayerScreen.web.tsx:679-697` cycles audio tracks; `legacy/electron-reference/mpvController.js:271-277` maps mpv audio tracks; `legacy/electron-reference/mpvController.js:338-340` sets `aid` to track id or `auto`.
- Browser fallback gap: HTML5/HLS.js playback has no audio-track selector in `src/screens/PlayerScreen.web.tsx:242-324`.

## Playback controls and back behavior

- Native: `src/screens/PlayerScreen.native.tsx:153-168` has a 20-second loading timeout; `src/screens/PlayerScreen.native.tsx:286-316` implements seek/toggle; `src/screens/PlayerScreen.native.tsx:426-517` handles hardware back/menu, play/pause, fast-forward, rewind, and overlay show/hide; `src/screens/PlayerScreen.native.tsx:539-777` renders mpv, loading/error overlays, EPG header, timeline, and controls.
- Web/Electron: `src/screens/PlayerScreen.web.tsx:101-124` implements seek/toggle for embedded mpv or HTML5; `src/screens/PlayerScreen.web.tsx:198-325` chooses Electron embedded mpv, external player, HLS.js, or direct video; `src/screens/PlayerScreen.web.tsx:423-469` maps remote/keyboard events; `src/screens/PlayerScreen.web.tsx:515-747` renders video/mpv overlays and controls.
- Electron mpv takeover legacy reference: `legacy/electron-reference/mpvController.js:1-15` documents takeover mode; `legacy/electron-reference/mpvController.js:44-63` locates `mpv` or Flatpak mpv; `legacy/electron-reference/mpvController.js:65-151` starts mpv with user-agent, geometry/fullscreen, start position, and JSON IPC; `legacy/electron-reference/mpvController.js:246-291` forwards progress, pause, EOF, tracks, and buffering; `legacy/electron-reference/mpvController.js:324-351` exposes pause/seek/track/stop commands.
