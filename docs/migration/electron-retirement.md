# Electron Retirement

Electron is retired from the `m3u-tv` architecture. The former implementation was preserved temporarily under `legacy/electron-reference/` as behavior evidence during the Flutter rewrite. That reference has since been deleted as part of the full React Native and legacy directory removal (2026-06-15). The Flutter app at `flutter_client/` is now the only active TV frontend.

## Rationale

- The active product direction was React Native TV and then Flutter for cross-platform playback parity. Electron was never the long-term release shell.
- Electron packaging was active through `electron:dev`, `electron:build`, and `electron-builder` metadata, but those scripts have been removed.
- Prior investigation found true Electron/mpv embedding blocked on Wayland in some environments, and Apple/tvOS mpv bridge work carries crash risk. Those risks were not worth keeping Electron in the release architecture.
- The legacy reference served as behavior documentation during the Flutter rewrite. Now that the Flutter app covers the primary feature surface, the reference has been deleted.

## What was removed

- `electron/` was moved to `legacy/electron-reference/` with `main.js`, `mpvController.js`, and `preload.js` preserved during Wave 1 of the Flutter rewrite.
- `legacy/electron-reference/` was deleted (along with the full `legacy/`, `src/`, `modules/`, `plugins/`, `desktop/`, and other RN/Expo directories) when the React Native app was removed.
- `package.json` no longer exists; all Node/Yarn/Expo tooling has been removed.

## Behavior coverage summary

The following behaviors were documented in the legacy reference and are now carried forward in the Flutter playback contract:

1. mpv launch and IPC lifecycle — covered in `android-playback-feasibility.md` and `playback-backend-matrix.md`.
2. Embedded playback/takeover — documented in `playback-backend-matrix.md`; Flutter desktop equivalent is gated pending Linux/Windows SDK work.
3. External player fallback — documented in `playback-backend-matrix.md`.
4. HLS/direct-video browser fallback — replaced by ExoPlayer (Android) and AVKit (Apple) native paths.
5. Audio track and subtitle track handling — documented in `android-playback-feasibility.md` and `apple-playback-store-feasibility.md`.
6. Fullscreen and quit keyboard shortcuts — handled by `AppShell` back-key mapping and Flutter window management.
7. Progress/resume — implemented in the Flutter app via m3u-editor progress API; see `m3u-editor-transcoding-contract.md`.

## Guardrails

- Do not reintroduce Electron as a desktop shell.
- Do not restore `electron:dev`, `electron:build`, or `electron-builder` configuration.
- Do not reference `legacy/electron-reference/` — it no longer exists.
