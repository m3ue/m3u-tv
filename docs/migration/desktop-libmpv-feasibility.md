# Desktop libmpv Feasibility

Task 7 proves the Flutter desktop path without Electron, external mpv windows, or reparented player processes. The spike adds a `m3u_tv/desktop_libmpv` native method channel on Linux, Windows, and macOS plus a Dart `DesktopLibmpvBackend` adapter in `flutter_client/lib/playback/desktop_libmpv_backend.dart`.

## Result matrix

| Target | Result | Native surface/layer | Render path | Fallback decision |
|---|---:|---|---|---|
| Linux Wayland | FAIL on executor | Flutter GTK window with owned in-process render path | Wayland/EGL libmpv render API | Server-transcode until GTK dev files and `libmpv.so` are packaged |
| Linux X11 fallback | FAIL on executor | Same Flutter GTK window path | X11/EGL libmpv render API fallback | Server-transcode until GTK dev files and `libmpv.so` are packaged |
| Windows | NOT RUN here, probe implemented | Runner-owned Win32 `HWND` | D3D11 native surface; Vulkan or ANGLE/OpenGL fallback if D3D11 interop blocks | Server-transcode until `mpv-2.dll` bundle is present |
| macOS | NOT RUN here, probe implemented | Runner-owned Cocoa `CALayer` | Metal layer via libmpv render API or MPVKit-equivalent wrapper | Server-transcode until `libmpv.2.dylib` or `MPVKit.framework` is bundled |

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

## macOS packaging

Decision: use a Metal-backed owned `CALayer` with libmpv render API if available. MPVKit is acceptable as an equivalent path if it keeps playback in-process and renders into app-owned Cocoa/Metal layers.

Required bundle artifacts:

- `Contents/Frameworks/libmpv.2.dylib`, or
- `Contents/Frameworks/MPVKit.framework` with embedded libmpv and FFmpeg dependencies.

Bundle steps:

1. Build or obtain a codesignable libmpv/MPVKit artifact for the deployment target.
2. Copy the dylib/framework into `Runner.app/Contents/Frameworks`.
3. Fix install names with `install_name_tool` so libmpv and FFmpeg dependencies resolve from `@rpath`/`@executable_path/../Frameworks`.
4. Codesign the app and every embedded dylib/framework together.
5. If notarization rejects private codec libraries, use server-transcode fallback for affected distributions.

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
