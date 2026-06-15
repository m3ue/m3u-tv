# m3u-editor Transcoding Contract

This document describes the m3u-editor proxy API surface as implemented by the Flutter fake server at `flutter_client/test/fakes/fake_m3u_editor_server.dart`. The contract covers the three proxy modes (`direct`, `server`, `local`) and the broadcast lifecycle endpoints. It is not yet implemented in the production Flutter playback path — the fake server exists to allow client contract tests to be written ahead of real integration.

## Modes

| Mode | Meaning | Proxy behavior |
| --- | --- | --- |
| `direct` | Passthrough/raw provider or media-server URL. | `/streams` creates a direct proxy stream. Broadcasts set `transcode: false`; FFmpeg seek is used unless seek is zero. |
| `server` | Media server performs transcoding, notably Plex/Emby/Jellyfin server-side HLS. | Stream URL may already include seek parameters. Broadcasts set `transcode: false`; FFmpeg seek is `0` when URL has `offset` or `StartTimeTicks`. Plex flow is sessionful: `/video/:/transcode/universal/decision` primes a session, `start.m3u8` is consumed by proxy, and stop/cleanup releases the session. |
| `local` | m3u-proxy/FFmpeg performs local transcoding. | `/transcode` creates a proxy stream. Broadcasts set `transcode: true` with codec/bitrate/preset hints. FFmpeg seek remains active. |

## Endpoints modelled by the Flutter fake server

### `GET /streams`

Lists active proxy streams.

Response fields:

- `success: bool`
- `streams: array<object>` containing stream records
- `total: int`

Failure states:

- `401 auth_failed` when `X-API-Token` is missing or invalid.

### `POST /streams`

Creates a direct passthrough stream.

Request fields:

- `url: string` required upstream URL
- `metadata: object` optional trace fields such as `playlist_uuid`, `channel_id`, `strict_live_ts`, `use_sticky_session`
- `user_agent: string|null`
- `headers: object|null`
- `failover_urls: array<string>|null`

Response fields:

- `stream_id: string`
- `stream_url: string` (`/stream/{stream_id}` in direct format)
- `mode: "direct"`
- `status: "active"`
- `metadata: object`

Failure states:

- `401 auth_failed`.

### `POST /transcode`

Creates server or local transcoded proxy stream.

Request fields:

- `url: string` required upstream URL
- `mode: "server"|"local"` for client contract tests (`direct` uses `/streams`)
- `profile: string|null` FFmpeg/profile identifier
- `resolver`, `resolver_args`, `cookies_path` for resolver-backed profiles
- `metadata: object`
- `headers: object|null`
- `user_agent: string|null`
- `failover_urls: array<string>|null`
- `video_codec`, `audio_codec` codec hints
- `session_id: string|null` used to reuse Plex sessions on retries

Response fields:

- `stream_id: string`
- `stream_url: string`; HLS-style `/hls/{id}/playlist.m3u8` for server transcode, direct `/stream/{id}` for local fake output
- `mode: "server"|"local"`
- `status: "starting"|"stalled"|"cancelled"|"failed"`
- `session_id: string|null`
- `metadata: object`

Failure states:

- `401 auth_failed`.
- `422 unsupported_codec` for codecs outside the fake supported set.
- `202` with `status: "stalled"` for a transcode that accepted work but is not progressing.

### `POST /transcode/{stream_id}/cancel`

Fake-only cancellation helper for client tests. The real contract treats broadcast stop and proxy stream deletion as the operational cancellation path, but the Flutter fake exposes explicit cancellation so retry/cancel client logic can be tested without changing m3u-editor server behavior.

Response fields:

- `stream_id: string`
- `status: "cancelled"`

Failure states:

- `404 stream_not_found`.

### `POST /broadcast/{network_uuid}/start`

Starts network HLS broadcasting through m3u-proxy.

Request fields from `NetworkBroadcastService::startViaProxy`:

- `stream_url: string`
- `seek_seconds: int`
- `duration_seconds: int`
- `segment_start_number: int`
- `add_discontinuity: bool`
- `segment_duration: int` default `6`
- `hls_list_size: int` default `20`
- `transcode: bool` (`true` only for `local` mode)
- `video_bitrate: string|null`
- `audio_bitrate: int|null`
- `video_resolution: string|null`
- `video_codec: string|null`
- `audio_codec: string|null`
- `preset: string|null`
- `hwaccel: string|null`
- `headers: object|null` provider-specific headers; Plex server transcode includes Plex session/playback headers, direct/local include token only
- `callback_url: string`
- `output_dir: string` from `proxy.broadcast_temp_dir`

Response fields:

- `network_id: string`
- `status: "started"`
- `ffmpeg_pid: int|null`
- `playlist_url: string`
- `transcode_session_id: string|null`

Failure states:

- `401 auth_failed`.
- `502 callback_failed` in the fake when callback delivery is configured to fail.
- Real m3u-editor records proxy errors in `broadcast_error`; boot recovery can treat some failures as transient and retry with the same Plex session ID.

### `GET /broadcast/{network_uuid}/status`

Checks whether a broadcast is active.

Response fields:

- `network_id: string`
- `status: "running"|"starting"|"stopped"|"failed"`
- `ffmpeg_pid: int|null`
- `playlist_url: string|null`

Failure states:

- `404` with `status: "stopped"` means no active broadcast.
- Non-404 proxy failures are treated as not running by m3u-editor.

### `POST /broadcast/{network_uuid}/stop`

Stops a broadcast and is the broadcast cancellation path.

Response fields:

- `network_id: string`
- `status: "stopped"`
- `final_segment_number: int`

Side effects in m3u-editor:

- Clears local broadcast process state unless preserving playback reference.
- Cleans up Plex transcode session when one was tracked.
- Calls `DELETE /broadcast/{network_uuid}` afterward to remove proxy files.

Failure states:

- Proxy stop failures are logged; local state is still cleared by `NetworkBroadcastService::stop`.

## Trust boundary for callbacks

`callback_url` is generated by m3u-editor for m3u-proxy to call back into Laravel (`/api/m3u-proxy/broadcast/callback`, or failover resolver equivalent). Treat this as an internal control-plane URL, not a client-facing playback URL. Flutter clients must not expose, accept, or relay arbitrary callback URLs from UI or remote input. If callbacks are reachable across networks, require the same trusted deployment boundary as m3u-proxy itself: private network or authenticated reverse-proxy path, token validation, and no public unauthenticated callback surface.

## Flutter fake coverage

The fake server in `flutter_client/test/fakes/fake_m3u_editor_server.dart` covers:

- Direct stream success through `/streams`.
- Server transcode success with session ID and HLS URL.
- Local transcode success with FFmpeg-style codec hints.
- Unsupported codec failure.
- Stalled transcode accepted but not progressing.
- Auth failure via `X-API-Token`.
- Callback failure during broadcast start.
- Cancellation through transcode cancel and broadcast stop.
