# Closed Captions in M3U TV — Learnings & Current Fix

Reference for future sessions. Last updated: 2026-11-15.

## TL;DR

- **Working fix:** `ccAwareExtractorsFactory()` in `Media3PlaybackPlugin.kt` —
  tells ExoPlayer's `TsExtractor` to expect in-band CEA-608/708 tracks via
  `DefaultExtractorsFactory.setTsSubtitleFormats(...)`. Needed when a
  broadcaster omits the ATSC caption service descriptor (`0x86`) from the
  PMT — without it Media3 creates no caption tracks even though A/53 CC
  data is present in-band.
- **File changed:** `flutter_client/android/app/src/main/kotlin/dev/sparkison/tv/Media3PlaybackPlugin.kt`
  (helper + `DefaultMediaSourceFactory(context, ccAwareExtractorsFactory())` at the player build).
- Verified on Google TV (onn 4K Pro): Channel B, which previously never showed a
  Subtitles button, now exposes CE-608/708 tracks.

## The bug

Two antenna channels with structurally identical streams (MPEG-2 video + 2×
AC-3, A/53 CC side-data present on every frame, no separate CC PID in the
PMT) behaved differently:

| Channel | ExoPlayer text tracks after prepare | Subtitles button |
|---------|--------------------------------------|------------------|
| Channel A | `application/cea-708` + `application/cea-608` | shown ✓ |
| Channel B (8.1) | none | never shown ✗ |

**Root cause (Media3 1.10.1 `DefaultTsPayloadReaderFactory.getClosedCaptionFormats`):**

For MPEG-2 video, `TsExtractor` always builds a `UserDataReader`, but the
caption formats it receives are resolved from the **PMT elementary-stream
descriptors**:

1. If `FLAG_OVERRIDE_CAPTION_DESCRIPTORS` is set → use the explicit list
   from `setTsSubtitleFormats`.
2. Otherwise parse PMT descriptors for tag **`0x86`** (ATSC caption service
   descriptor).
3. If tag `0x86` is present → build CEA-608/708 formats from it.
4. If absent → fall back to the `closedCaptionFormats` field, **empty by
   default**.

| Channel | PMT caption descriptor (0x86)? | Formats returned | Text tracks |
|---------|-------------------------------|------------------|-------------|
| Channel A | yes | from PMT descriptor | created ✓ |
| Channel B | **no** | empty (default) | **none** ✗ |

Both streams carry A/53 CC in-band in the video PES — the difference is
purely whether the broadcaster **declared** the caption service in the PMT.
Without that declaration Media3 never creates a caption track output, so no
Subtitles button ever appears for the session.

**Why the fix works:** `setTsSubtitleFormats(...)` populates the fallback
list used in step 4. When the PMT descriptor is absent (Channel B), our four
formats (CEA-608 CC1/CC2, CEA-708 services 1/2) are used instead of empty.
When the descriptor is present (Channel A), it still wins (step 3) — so behavior
on already-working channels is unchanged.

> Earlier notes blamed a "prepare window timing" issue — that was wrong.
> Track creation happens at PMT parse time; the real cause is a missing PMT
> caption service descriptor, not late-arriving CC data.

## Why other approaches were ruled out

1. **ffprobe shows no subtitle streams** on either channel — expected. ATSC
   CC is in-band A/53 inside the video PES, not a demuxed stream. Don't
   conclude "no captions" from `ffprobe -show_streams`.
2. **`readeia608` filter dumps showed no caption codes** during test windows —
   caption text is content-dependent (often empty between dialogue); absence
   in a 20s sample doesn't prove the stream lacks CC capability.
3. **Preferring mpv for live** (`preferMpv: true`): mpv/ffmpeg does extract
   A/53 robustly, but playback became choppy/horrible on the tuner streams —
   rejected. `preferMpv` stays VOD-only (`player_source_settings.dart`).
   - Side experiment: a `track-list` property observer + `TRACKS_CHANGED`
     event chain (`MpvPlayerCore.kt` + `mpv_native_event.dart`) was built to
     re-read mpv tracks late. **Removed** — unnecessary once the ExoPlayer
     fix landed, and mpv isn't the live-TV backend anyway.
4. **Server-side (m3u-editor)**: proxy uses stream **copy** — CC bytes pass
   through untouched. Nothing to fix in the editor.

## Backend architecture notes (Android)

- Backend order: **ExoPlayer first, mpv second** (`playback_capabilities.dart`
  `forPlatform(android)`). `preferMpv` only reorders for non-live when
  `vodPlayerSync == mpv`.
- DVR: `type: recording.isInProgress ? 'live' : 'vod'`
  (`dvr_recordings_screen.dart:1215`) → in-progress DVR plays as live
  (ExoPlayer); completed DVR is VOD-like (ExoPlayer unless VOD=mpv).
- ExoPlayer live URLs hint `APPLICATION_M3U8` first; when the server serves
  raw TS, `retryAsTs` re-prepares as `VIDEO_MP2T` (the `#EXTM3U` error is
  expected noise, not a failure).
- CC tracks are read from `player.currentTracks` groups with
  `type == TRACK_TYPE_TEXT` in `emitTrackSnapshot()`; the Dart side applies
  them on every event (`android_playback_adapter.dart`).

## European captions (scope note)

- **DVB bitmap subs** (typical EU): separate PMT stream →
  `DvbSubtitleReader` — unaffected by the CEA fix (different discovery path).
- **EBU teletext**: Media3 ships no teletext decoder — never supported, no
  regression.
- Watch-item: if `setTsSubtitleFormats` eagerly creates declared CEA entries,
  EU streams could show empty CC menu entries (cosmetic). Verified worth
  checking on an EU source if available.

## Open feature work (requested 2026-11-15)

Caption display controls under Playback settings, Media3/SubtitleView path:

1. **Position** — top vs bottom (cue line override in `onCues` /
   SubtitleView styling)
2. **Text color** — currently white (`SubtitleView.setForegroundColor`)
3. **Background color** — currently black; option for **transparent**
4. **Default captions ON** — auto-select first text track when tracks appear
   and the setting is enabled (currently defaults off every session)

Settings go in `ViewSettingsService` (pattern: `hdrEnabledKey`,
`deinterlaceKey`) + rows in `playback_settings_page.dart`. Native values
reach `Media3PlaybackPlugin` via the source/arguments map, applied in
`attachSubtitleView()` / `onCues`.

Scope: Media3/SubtitleView path only (covers live TV + DVR by default).
mpv backends (desktop/Apple/VOD-when-mpv-preferred) use separate `sub-*`
mpv options — out of scope unless requested.

## Implemented (2026-11-15, rev 2 — color/position fixes + sub-menu)

Settings live under **Settings → Playback → Player → Captions** (one entry
row with chevron → sub-page; Playback section subtitle is now
"Player, proxy, DVR, and captions"):

| Setting | Key (ViewSettingsService) | Values (default first) |
|---------|---------------------------|------------------------|
| Captions by default | `m3ue_tv_captions_default` | off / on |
| Caption position | `m3ue_tv_caption_position` | bottom / top |
| Caption text color | `m3ue_tv_caption_text_color` | white / yellow |
| Caption background | `m3ue_tv_caption_bg_color` | black / transparent |

**Files changed:**

- `lib/services/view_settings_service.dart` — keys, async + sync getters, setters
- `lib/main.dart` — preload the four async getters at startup (required for
  `*Sync` getters; see issue #314 comment for why)
- `lib/l10n/app_{en,de,es,fr,zh}.arb` — `settingsCaptions` + 11 caption keys;
  `settingsPlaybackSubtitle` updated; regenerated via `flutter gen-l10n`
- `lib/features/settings/sections/playback_settings_page.dart` — single
  Captions row → `pushSettingsSubpage` with switch + 3 picker rows
  (wrapped in `ListenableBuilder(service)` so subtitles refresh live). Row
  subtitle summarizes all four settings: `On (Bottom · Yellow/Black)`
- `lib/playback/player_adapter.dart` — `PlaybackSource` fields + copyWith
- `lib/features/player/player_source_settings.dart` — `applyPlayerSourceSettings`
  copies settings → source
- `lib/playback/android_playback_adapter.dart` — source-map keys to native
- `android/.../Media3PlaybackPlugin.kt`:
  - `PlayerState`: caption fields + `captionsAutoSelected` flag
  - `load()`: reads the source map into `PlayerState`
  - `applyCaptionStyle()`: white+black keeps `setApplyEmbeddedStyles(true)`
    (native cue colors); any other pair builds **`CaptionStyleCompat`
    via its public 6-arg constructor** `(fg, bg, windowColor,
    EDGE_TYPE_OUTLINE, edgeColor, Typeface.DEFAULT)` — the old reflective
    `CaptionStyle.Builder` path returned null on failure (API-37 stub jar
    omits the nested class), silently leaving colors stuck white-on-black
  - `attachSubtitleView()` + post-`states[playerId] = state`: apply style
  - `onCues()`: **vertical** forced — top:
    `setLine(0f, LINE_TYPE_FRACTION).setLineAnchor(ANCHOR_TYPE_START)`;
    bottom: `setLine(1f, LINE_TYPE_FRACTION).setLineAnchor(ANCHOR_TYPE_END)`
    (decoder's own row placement often lands mid-screen, not at the bottom).
    **Horizontal** forced to center for text cues (`setPosition(0.5f)` +
    `ANCHOR_TYPE_MIDDLE` + `ALIGN_CENTER`) — CEA-608 carries its own start
    column/justification per caption, which is why placement flickered
    between left and center; bitmap cues (null text) keep the decoder's
    placement. When custom colors are active, cue text is re-set as a plain
    `toString()` so embedded `ForegroundColorSpan`s are stripped and
    `CaptionStyleCompat` wins
  - `emitTrackSnapshot()`: "captions by default" — once per load, selects the
    first text track when none selected; flag set before `selectTrack` to
    prevent re-entrant loops (its own snapshot emission re-enters)

**Not covered:** mpv backends (desktop/Apple/VOD-when-preferred) — would use
mpv's own `sub-*` options (color, border-color, margin-v, sub-pos) wired the
same way as `deinterlace`/`prebufferLive` if wanted later.

