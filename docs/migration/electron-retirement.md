# Electron Retirement

Electron is retired from the active `m3u-tv` target architecture. The former implementation remains available only as a legacy behavior reference under `legacy/electron-reference/`.

## Rationale

- The active product direction is React Native TV today and the Flutter rewrite path for cross-platform playback parity.
- Electron packaging was an active release path through `electron:dev`, `electron:build`, and `electron-builder` metadata, but desktop Electron is no longer the target shell.
- Prior investigation found true Electron/mpv embedding blocked on Wayland in some environments, and Apple/tvOS mpv bridge work carries crash risk. Those risks should not keep Electron in the release architecture.
- The legacy code still documents important playback behavior, so it must be preserved until replacement parity tests cover the same cases.

## What changed

- `electron/` moved to `legacy/electron-reference/` with `main.js`, `mpvController.js`, and `preload.js` preserved.
- `package.json` no longer exposes `electron:dev` or `electron:build` scripts.
- Electron packaging metadata was removed from `package.json`; active release output should not depend on `electron-builder` or `electron/**/*`.
- README platform guidance now marks Electron as retired reference-only code.

## Behavior coverage required before deleting the reference

Do not delete `legacy/electron-reference/` until parity tests and implementation notes cover these behaviors:

1. mpv launch and IPC lifecycle, including startup failure handling and cleanup.
2. Embedded playback/takeover behavior, including window geometry matching and failure fallback.
3. External player fallback ordering for mpv, VLC, and system-default playback.
4. HLS/direct-video browser fallback expectations for web-compatible streams.
5. Audio track enumeration/selection and subtitle track enumeration/selection.
6. Fullscreen and quit keyboard shortcuts that existed in the Electron shell.
7. Progress/resume interactions for VOD and episode playback.

## Guardrails

- Do not reintroduce Electron as a new desktop shell.
- Do not add active `electron:dev` or `electron:build` scripts back to the root package.
- Do not wire `legacy/electron-reference/` into release artifacts.
- Treat the reference as read-only behavior evidence unless a migration task explicitly updates documentation around it.
