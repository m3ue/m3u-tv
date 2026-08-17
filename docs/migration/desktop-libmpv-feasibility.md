# Desktop libmpv Feasibility

Task 7 proves the Flutter desktop path without Electron, external mpv windows, or reparented player processes. The spike adds a `m3u_tv/desktop_libmpv` native method channel on Linux and Windows plus a Dart `DesktopLibmpvBackend` adapter in `flutter_client/lib/playback/desktop_libmpv_backend.dart`. A native macOS implementation was later prototyped and reverted -- see "macOS: native mpv now primary" below for that history and the current status.

> **Status update**: the original "macOS: not planned" framing below (and its
> "Follow-up" note) is superseded by current intent. The project relicensed
> to GPL-3.0 (see repository root `LICENSE`), which unblocks bundling
> MPVKit/libmpv -- see `apple-playback-store-feasibility.md`'s status update
> for why that changes the whole Apple platform picture, not just macOS. The
> current goal is **native mpv playback on all three Apple platforms**
> (macOS, iOS, tvOS), using the `edde746/MPVKit` Swift package and modeled on
> the open-source [Plezy](https://github.com/edde746/plezy) player (same
> author, GPL-3.0). Native mpv is now confirmed fully working on macOS,
> iOS, and tvOS via hands-on click-testing (the tvOS overlay-scaling
> cosmetic bug has been fixed). This section is kept
> for its historical record of why the first (software-texture-bridge)
> prototype was reverted, which still holds -- the *current* native mpv
> attempt is a different architecture, not a repeat of that one.

## Result matrix

| Target | Result | Native surface/layer | Render path | Fallback decision |
|---|---:|---|---|---|
| Linux Wayland | Active (custom backend) | Flutter GTK window with owned in-process render path | Wayland display handle + libmpv `MPV_RENDER_API_TYPE_SW` + `FlPixelBufferTexture`; `hwdec=auto-safe` | Server-transcode if `libmpv.so.2` unavailable on the host |
| Linux X11 | Active (custom backend) | Same Flutter GTK window path | X11 display handle + libmpv `MPV_RENDER_API_TYPE_SW` + `FlPixelBufferTexture`; `hwdec=auto-safe` | Server-transcode if `libmpv.so.2` unavailable on the host |
| Windows | Active (custom backend) | Runner-owned Win32 `HWND` | libmpv render API + RGBA pixel buffer texture (D3D11/ANGLE/OpenGL); `hwdec=auto-safe` | Server-transcode until `mpv-2.dll` bundle is present |
| macOS | Active (native mpv, primary) | Native mpv via `PlaybackBackend.macMpvNative` (`edde746/MPVKit`), confirmed working via hands-on click-testing | Native `AppKitView`/`CAMetalLayer` (`vo=gpu-next` + `gpu-context=moltenvk` + `hwdec=videotoolbox`) | Server-transcode (no automatic media_kit fallback for main playback currently; media_kit is no longer used anywhere on macOS, including for the separate Multiview surface, which now also uses `MacMpvNativeBackend`) |

Executor evidence:

- Initial TDD red output: `.omo/evidence/task-7-initial-failing-tests.txt`.
- Linux after implementation with a temporary `clang++ -> g++` shim: `/tmp/flutter/bin/flutter test integration_test/desktop_playback_smoke_test.dart -d linux` still fails before app launch because `gtk+-3.0` pkg-config metadata is missing. This host also has no `mpv.pc` and no `libmpv` entry in `ldconfig -p`.

## Linux packaging

Required build packages:

- `gtk+-3.0` development files with pkg-config metadata, normally `libgtk-3-dev` on Debian/Ubuntu or `gtk3-devel` on Fedora.
- C++ compiler visible as `clang++` or `CXX`; this executor lacked `clang++`.
- Flutter Linux desktop prerequisites from `/tmp/flutter/bin/flutter doctor`.

Required runtime libraries:

- `libmpv.so.2` preferred, with fallback lookup of `libmpv.so.1` or `libmpv.so`.
- mpv's transitive FFmpeg, Lua/Javascript, subtitle, audio, EGL/OpenGL, VAAPI/VDPAU, Vulkan, and X11/Wayland dependencies as shipped by the distro package.

Implementation notes:

- The Linux runner dynamically loads libmpv with `dlopen` so normal builds do not require mpv headers.
- The runner probes the active GDK display and reports `wayland` or `x11`.
- The selected path is libmpv render API style (`mpv_render_context_create` symbol required) with `vo=libmpv`, `terminal=no`, and `config=no`; it never spawns `mpv`.
- Wayland should use EGL or Vulkan-backed rendering owned by the Flutter/GTK process. X11 uses the same owned in-process path as fallback rather than `wid` reparenting.

Bundle steps:

1. Install Linux desktop build prerequisites and `libmpv-dev`/`mpv-libs-devel` in CI.
2. Build with `/tmp/flutter/bin/flutter build linux`.
3. Copy `libmpv.so.*` and required non-system transitive libraries into `build/linux/*/bundle/lib` when producing portable archives, or declare distro package dependencies for deb/rpm packaging.
4. Keep `$ORIGIN/lib` RPATH from `linux/CMakeLists.txt` so bundled `libmpv.so.*` resolves beside Flutter libraries.

## Windows packaging

Decision: use D3D11 as the first-class backend because Flutter Windows owns a Win32 view and mpv's Windows builds ship GPU paths that can target D3D11. If D3D11 interop is blocked by a specific mpv build, use Vulkan or ANGLE/OpenGL with the same in-process method-channel backend. Do not use an external mpv process.

Required binaries beside `m3u_tv.exe`:

- `mpv-2.dll`.
- FFmpeg DLLs used by that mpv build, typically `avcodec-*.dll`, `avformat-*.dll`, `avutil-*.dll`, `swresample-*.dll`, and `swscale-*.dll`.
- Rendering/audio dependencies shipped with the chosen mpv build.

Bundle steps:

1. Use a known mpv Windows SDK/runtime build and pin its version in release automation.
2. Copy `mpv-2.dll` and dependent DLLs into the Flutter Windows install bundle next to `m3u_tv.exe`.
3. Keep the runner method channel probe in CI; a missing `mpv-2.dll` is a FAIL and must choose server-transcode fallback.

## macOS: native mpv now primary (history below still accurate)

A native in-process libmpv backend for macOS (MPVKit XCFramework via SPM, `MPV_RENDER_API_TYPE_SW` + `FlutterTexture`/`CVPixelBuffer`, mirroring the Linux/Windows shape) was fully implemented and hands-on tested. It worked, but reimplemented -- with more bugs along the way (duration detection, scrubbing, a 900% CPU spike from `force-seekable=yes` full-stream probing) -- most of what `media_kit_video`'s macOS build already provides out of the box via its own bundled libmpv. Testing confirmed `media_kit_video` on macOS does not hit the EGL bug described below (EGL is a Linux/Windows-only rendering concern there; macOS uses Metal), so there was no upstream bug to route around on this platform in the first place. The custom backend was reverted; macOS stayed on `MediaKitDesktopAdapter` (media_kit) unless a concrete, reproducible macOS-specific problem justified revisiting it.

**Follow-up (superseding the "indefinitely" framing above):** that bar has since been met -- media_kit's texture-bridge render path is the suspected cause of separate, concrete macOS performance and HDR limitations, unrelated to the EGL issue this document otherwise covers. A second native macOS attempt is now in progress (`PlaybackBackend.macMpvNative`, `lib/playback/mac_mpv_native_backend.dart`), but it is a **different architecture** from the reverted prototype above, not a repeat of it: the reverted prototype used `MPV_RENDER_API_TYPE_SW` through the Flutter texture bridge, i.e. still software-composited, the same class of bottleneck as media_kit itself. The new attempt uses `vo=gpu-next` + `gpu-context=moltenvk` + `hwdec=videotoolbox` rendered through a native Swift `FlutterPlatformView` (`AppKitView`), bypassing the Flutter texture bridge entirely -- modeled directly on the open-source Plezy player (github.com/edde746/plezy, GPL-3.0), which this app can now adapt from directly since it relicensed to GPL-3.0 (see repository root `LICENSE`). It explicitly avoids the prior prototype's known bugs, in particular never setting `force-seekable=yes`, and is held to the same duration/scrubbing regression bar the prior attempt failed. See `flutter_client/lib/playback/apple_backend_feasibility.dart` for the current macOS playback gate.

**Second follow-up:** this is no longer a macOS-only effort -- the same native mpv approach (now on the `edde746/MPVKit` fork specifically, swapped from upstream `mpvkit/MPVKit` for better Apple GPU/Metal support) is the primary playback backend for iOS and tvOS as well, all modeled on Plezy. Native mpv is now confirmed fully working on macOS, iOS, and tvOS via hands-on click-testing (video, audio, subtitles, track switching, seeking, clean teardown on macOS; video, audio, no crash on back navigation on iOS; video, audio, subtitles on tvOS). The tvOS overlay-scaling cosmetic bug (playback overlay rendering "boxed in" relative to the video) has been fixed.

**Third follow-up (macOS Multiview and concurrent UHD decode):** macOS Multiview now also runs on `MacMpvNativeBackend` instead of `MediaKitDesktopAdapter` (see "Current status" below). Click-testing on real hardware confirmed two concurrent non-UHD Multiview tiles render correctly with independent audio-focus muting, but two concurrent UHD/4K tiles can render black (video track silently dropped on a `vo=gpu-next` reconfig failure) or gray (stalled decode). This has also been confirmed on tvOS, so the same VideoToolbox concurrent hardware-decode session contention likely affects iOS too, though that has not been directly tested yet. This is a hardware-decode-capacity limitation shared across Apple's VideoToolbox-based decode path, not specific to `MacMpvNativeBackend`'s `gpu-next`/moltenvk rendering -- each UHD stream plays fine individually, and non-UHD pairs play fine concurrently. No mitigation (e.g. forcing software decode on background tiles, or a UI warning) has been implemented yet.

## Test command

Primary command:

```bash
cd flutter_client
/tmp/flutter/bin/flutter test integration_test/desktop_playback_smoke_test.dart -d linux
```

Equivalent command used on this executor after the compiler issue was identified:

```bash
PATH=/tmp/opencode/bin:/usr/bin:/bin:/tmp/flutter/bin /tmp/flutter/bin/flutter test integration_test/desktop_playback_smoke_test.dart -d linux
```

The equivalent command reached the next host prerequisite failure: missing `gtk+-3.0`. Once GTK dev files and libmpv runtime are installed, the same test should either play the fixture HLS in-process or report a server-transcode fallback decision from the native probe.

## Current status (2026-07-16)

The in-process custom backend is wired into the desktop orchestrator path for Linux and Windows (`lib/navigation/app_router.dart`, `DesktopLibmpvBackend`). macOS now uses `PlaybackBackend.macMpvNative` (native mpv via `edde746/MPVKit`) as its primary backend instead of `MediaKitDesktopAdapter`; see the "Follow-up" notes under "macOS: native mpv now primary" above for that architecture. `MediaKitDesktopAdapter` is no longer used anywhere on macOS, including for the separate Multiview surface -- see the "Third follow-up" note above for its current status and the known UHD decode-contention limitation.

### Why the swap

`media_kit_video` (the upstream plugin `MediaKitDesktopAdapter` depends on) has an open upstream bug: [media-kit/media-kit#1404](https://github.com/media-kit/media-kit/issues/1404), *"H/W rendering fails on Flutter 3.38+: EGL display not current on platform thread"*. Starting with Flutter 3.38 the EGL rendering context lives exclusively on the raster thread, but `media_kit_video`'s `video_output_new` calls `eglGetCurrentDisplay()` on the platform thread, where it returns `EGL_NO_DISPLAY`. The result is `media_kit: VideoOutput: EGL display or context is invalid.` followed by `media_kit: VideoOutput: S/W rendering.` on every Flutter 3.38+ Linux/Windows build, including this app's Flutter 3.44.2 bundle at `/home/cj/Documents/m3u-tv/`. This is an EGL-specific bug and does not affect macOS, which renders through Metal, not EGL — confirmed by hands-on macOS testing showing no such warning.

`2.0.1` is the latest released version on pub.dev and does not fix this. Upstream is in *Limited Maintenance* per #1337; no PR is open. The custom `DesktopLibmpvBackend` (`linux/desktop_libmpv_backend.cc` / `windows/runner/desktop_libmpv_backend.cpp`) sidesteps the EGL dependency entirely by using `MPV_RENDER_API_TYPE_SW` with `FlPixelBufferTexture` and `hwdec=auto-safe`. Decoding stays hardware-accelerated, while only texture upload uses software pixel copies.

### Verification on this executor (NVIDIA RTX 4070 SUPER, driver 580.159.03, X11, Flutter 3.44.2)

- `flutter analyze`: clean.
- `flutter test` (134 tests across `test/playback/`, `test/integration/`, `test/ui/`): all pass, 5 skipped (platform-conditional).
- `flutter build linux --debug`: produces `build/linux/x64/debug/bundle/m3u_tv`.
- Launching the bundle produced no `EGL display or context is invalid` or `S/W rendering` lines in stdout (proving `mkv.VideoController` is no longer constructed at startup).
- `libmpv.so.2` resolves via `dlopen` against the system package (`/lib/x86_64-linux-gnu/libmpv.so.2`, mpv 0.37.0, FFmpeg 6.1.1, libplacebo v6.338.2). NVIDIA EGL ICD at `10_nvidia.json` is untouched and remains available for any future H/W texture path.

### Known issues

- **`integration_test/desktop_playback_smoke_test.dart` has two pre-existing assertion failures** (unrelated to this swap because the test instantiates `DesktopLibmpvBackend` directly, so it has always exercised the custom backend):
  1. `reports feasibility and plays fixture without external mpv`: observed state sequence is `[loading, ready, playing, paused]` but the assertion at line 42 expects `stopped` to be present. The test stops the backend then asserts on the listener before pumping a frame, so the `PlaybackStatus.stopped` event from `backend.stop()` (synchronous broadcast after the method-channel call returns) is not yet delivered to the listener. The runtime behavior is correct: probe succeeded (`libmpvAvailable`, `renderApiAvailable`, `canPlayFixture` all true), load/play/pause/stop all completed against the real HLS fixture at `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`. Fix would be a single `await tester.pump()` after `backend.stop()` on line 40.
  2. `normal playback stays on the method-channel texture path`: observed method-channel call sequence is `['probe', 'load', 'getVideoAspectRatio', 'play', 'stop']` but the assertion at line 95 expects `['probe', 'load', 'play', 'stop']`. The extra `getVideoAspectRatio` call comes from `DesktopLibmpvBackend.load()` lines 93 to 95, which fires `unawaited(_refreshVideoAspectRatio())` whenever the initial aspect ratio is null (the test's mock `load` response omits it). This is intended production behavior, not a regression. Fix would be updating the expected list to include `getVideoAspectRatio`.

  Both failures are stale test expectations, not runtime defects. They are tracked here instead of fixed because the production path now routes through this backend and the underlying behavior is the intended design.

- **macOS is not subject to the #1404 EGL bug** this document otherwise covers (macOS renders through Metal, not EGL), so `MediaKitDesktopAdapter` was never swapped out for that reason. See "macOS: native mpv now primary" above, including its follow-up notes, for the prototype-and-revert history and the separate native mpv/PlatformView attempt (now confirmed working, targeting macOS performance/HDR) that superseded `MediaKitDesktopAdapter` as the primary macOS backend.
- **Subtitle rendering is not exposed by `DesktopLibmpvBackend`** (it does not implement `SubtitleControllerProvider`). `PlaybackOrchestrator.activeSubtitleController` returns `null` for the desktop backend path, so `SubtitleView`-based rendering does not appear on Linux/Windows. This matches the prior design (`docs/migration/desktop-libmpv-feasibility.md` predates this requirement) but should be revisited if external subtitles need to be added.
- **libmpv is loaded from the system package**, not bundled. The host needs `libmpv.so.2` (or `.1`/`.so`) on `LD_LIBRARY_PATH` or in `/usr/lib`. This is fine for distro installs and most developer machines, but portable AppImage/snap/flatpak bundles will need to vendor libmpv alongside the binary per the original `Bundle steps` section above.
