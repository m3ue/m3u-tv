# License Notices Checklist

This document records the third-party dependency license notices that must be included with every distributed artifact (Play Store, App Store, Microsoft Store, sideload, or direct download). It is a release gate: no public distribution is complete until the matching notices are reviewed, generated, and saved with the signed artifact evidence.

## App License

- The M3U TV Flutter client is licensed under **GPL-3.0**, with an additional permission under GPLv3 section 7 that allows distribution through the Apple App Store, Apple TV App Store, and Google Play Store despite those stores' additional restrictions, provided the complete corresponding source is also made available through an unrestricted channel (this repository).
- The full license text, including the store-distribution exception, is available at the repository root: `LICENSE`.
- Source-availability, notice-preservation, and copyleft obligations apply to all distributed artifacts. Contributor sign-off for the relicense from the prior CC BY-NC-SA 4.0 license was obtained from all contributors with commits in the tree.

## Android Playback Dependencies

### Media3 / ExoPlayer
- **Scope**: Android and Android TV playback backend.
- **License**: Apache License 2.0 (AndroidX).
- **Notice requirement**: Include AndroidX/Media3 license notices in the app bundle or provide them through the Play Console third-party notices section.
- **Status**: Active default Android playback path.
- **Gate**: Verify `media3-exoplayer`, `media3-exoplayer-hls`, `media3-session`, and `media3-ui` notices are present in generated or bundled form before release.

### Flutter SDK and Flutter Plugins
- **Scope**: Cross-platform UI, engine, and plugin dependencies.
- **License**: BSD-3-Clause (Flutter SDK and most first-party plugins).
- **Notice requirement**: Include Flutter SDK and plugin license notices. The `flutter build` command generates `flutter_assets/NOTICES.Z` which satisfies this for most plugins.
- **Status**: Active on all platforms.
- **Gate**: Verify `NOTICES.Z` or equivalent is present in release artifacts.

## Desktop Playback Dependencies

### mpv / libmpv
- **Scope**: Linux and Windows desktop in-process playback (`DesktopLibmpvBackend`), and Android native mpv (`androidMpv`, `dev.jdtech.mpv` bindings) as the primary Android playback path.
- **License**: LGPL-2.1+ (libmpv client library). The mpv core contains GPL-2.0+ components.
- **Notice requirement**: If libmpv is linked dynamically, include LGPL notices and provide a written offer for the source if distributing binaries. If linked statically or if GPL-only components are included, the entire artifact may become GPL-derived.
- **Status**: Active on Android, Linux, and Windows desktop as the primary playback backend on each. Linux/Windows both render via a GPU path now (Wayland `wl_subsurface` / ANGLE `FlutterDesktopGpuSurfaceTexture` respectively), confirmed on real hardware, with automatic runtime fallback to the original SW pixel-buffer path.
- **Gate**: Do not ship GPL-only binaries or GPL-derived code in a store/direct-download artifact unless the release owner explicitly accepts GPL distribution obligations and records that decision in release evidence.

### ANGLE (Windows GPU-texture rendering path)
- **Scope**: Windows desktop only -- `windows/runner/angle_surface_manager.{h,cc}`, the GL-to-D3D11 translation layer that lets mpv's OpenGL render output become a `FlutterDesktopGpuSurfaceTexture`.
- **License**: BSD-3-Clause (Google, ANGLE itself). The pre-packaged release this project fetches (`alexmercerind/flutter-windows-ANGLE-OpenGL-ES` v1.0.1) also bundles SwiftShader (Apache-2.0) components, though this project only bundles ANGLE's own D3D11-backed DLLs (`libEGL.dll`, `libGLESv2.dll`, `d3dcompiler_47.dll`, `zlib.dll`), not SwiftShader's software-Vulkan fallback (`vk_swiftshader.dll`/`vulkan-1.dll`).
- **Status**: Active dependency, confirmed working on real Windows hardware.
- **Gate**: Include ANGLE (and, if ever bundled, SwiftShader) attribution notices in the Windows artifact. Not yet reviewed.

### FFmpeg
- **Scope**: Bundled with libmpv on Linux/Windows desktop.
- **License**: LGPL-2.1+ or GPL-2.0+ depending on build configuration (codecs, filters, and protocols enabled).
- **Notice requirement**: Include FFmpeg license notices. If using GPL-enabled FFmpeg build, the same GPL policy as mpv applies.
- **Status**: Desktop-only, bundled as part of libmpv runtime.
- **Gate**: Verify the exact FFmpeg build flags and license before distribution. GPL-enabled FFmpeg makes the artifact GPL-derived.

### libass
- **Scope**: Subtitle rendering in libmpv.
- **License**: ISC / BSD-style (libass itself). Some dependencies may have different licenses.
- **Notice requirement**: Include libass license notices in bundled desktop artifacts.
- **Status**: Desktop-only, bundled with libmpv.
- **Gate**: Verify libass and its dependency notices are present.

### SpatialAudioBridge
- **Scope**: Linked into the iOS and tvOS `Libmpv.framework` from mpv-build 8ad6d9b on (mpv-build 45b6173, `ao_spatial`). Not on macOS. The app does not select `ao=spatial`, so it is linked but unused.
- **License**: Apache-2.0, with MIT/Apache-2.0 Rust crates and an FFmpeg-derived DTS decoder (`dca`) under LGPL-2.1-or-later. All GPL-3.0 compatible.
- **Notice requirement**: The framework ships the full notices as `Libmpv.framework/LICENSE.SpatialAudioBridge`.
- **Gate**: Include those notices wherever the libmpv/FFmpeg/libass notices are listed for iOS and tvOS.

## Apple Playback Dependencies

### AVKit / AVPlayer
- **Scope**: iOS, iPadOS, and tvOS playback (primary backend). macOS moves to a native mpv/MPVKit backend -- see MPVKit entry below and the Desktop Playback Dependencies section.
- **License**: Apple proprietary framework; no additional third-party notice required beyond Apple standard terms.
- **Status**: Safe, permanent path for iOS/iPadOS/tvOS.
- **Gate**: No additional license gate beyond standard Apple distribution terms.

### MPVKit (Active, macOS, iOS, and tvOS)
- **Scope**: Native mpv playback as the **primary** backend on all three Apple platforms -- macOS (`macMpvNative`, `AppKitView`, `vo=gpu-next` + `gpu-context=moltenvk` + `hwdec=videotoolbox`) and iOS/tvOS (`appleMpvNative`, `vo=avfoundation` + `hwdec=videotoolbox`), replacing media_kit's texture-bridge render path to address performance and HDR limits. `AppleAvKitBackend` (AVKit) remains the automatic fallback on iOS/tvOS only; macOS has no automatic fallback.
- **License**: LGPL-3.0 (use the plain `MPVKit` SPM product, not the `MPVKit-GPL` product, since Samba support isn't needed).
- **Status**: Active dependency on all three platforms. The app itself is now GPL-3.0 (see App License above, with an App Store distribution exception), which resolves the prior GPL/App-Store-incompatibility blocker that kept iOS/tvOS "not planned."
- **Gate**: Include MPVKit/libmpv/FFmpeg/libass license notices (same content as the desktop mpv notices above) in the macOS, iOS, and tvOS artifacts. Verify the LGPL-3.0 product is used, not the GPL-3.0 Samba-enabled one, unless that's a deliberate future choice.

### Plezy reference code (Apple native mpv backends)
- **Scope**: `github.com/edde746/plezy` (GPL-3.0) is used as a direct implementation reference/port source for the macOS `vo=gpu-next`/MoltenVK PlatformView backend and the iOS/tvOS `vo=avfoundation` backend, not merely conceptual guidance.
- **License**: GPL-3.0.
- **Status**: Active. Permitted because this app is GPL-3.0.
- **Gate**: Preserve upstream copyright/license notices in any ported Swift source files; keep the resulting m3u-tv code GPL-3.0 (or GPL-compatible).

## GPL Policy Gate

- **Rule**: This app is GPL-3.0. GPL-only binaries and GPL-derived code (mpv core, GPL-enabled FFmpeg builds, Plezy-derived Swift source, statically linked GPL components) may ship in store/direct-download artifacts as normal GPL-3.0 distribution -- the App Store/Play Store additional permission in `LICENSE` covers store-terms compatibility. This replaces the prior blanket "do not ship GPL" prohibition, which predated the relicense.
- **Scope**: Applies to mpv core, GPL-enabled FFmpeg builds, MPVKit-GPL (if ever used instead of the plain LGPL product), and any statically linked GPL components.
- **Requirement**: Every such release must make the complete corresponding source available through an unrestricted channel (this repository) alongside the store artifact, and preserve upstream notices per each component's obligations above.
- **Evidence requirement**: Any release that includes GPL components must have a signed-off license review document saved with the artifact evidence, confirming source availability and notice preservation.

## Release Artifact Checklist

Before any store or sideload release, verify:

- [ ] `LICENSE` (GPL-3.0 with App Store distribution exception) is included or referenced in the artifact metadata.
- [ ] Media3/ExoPlayer AndroidX notices are present (via `NOTICES.Z` or explicit third-party notices file).
- [ ] Flutter SDK and plugin notices are present (via `NOTICES.Z` or explicit third-party notices file).
- [ ] Desktop/Android/Apple artifacts: libmpv, FFmpeg, and libass notices are present and the exact license (LGPL vs GPL) is verified; Windows artifacts additionally include ANGLE notices; macOS/iOS/tvOS artifacts additionally include MPVKit notices.
- [ ] Complete corresponding source for the artifact is available through this repository (satisfies both LGPL source-offer and GPL source-availability obligations).
- [ ] Any GPL-only components included (MPVKit-GPL, Plezy-derived source, etc.) have release-owner acceptance and evidence on file, even though GPL distribution itself is now the app's normal default.
- [ ] All notices are saved with the signed artifact evidence under `.omo/evidence/` or equivalent release evidence directory.

## Honest Blockers

- License notice generation and review are not automated in this repository. Each platform release must manually verify the generated notices before distribution.
- Desktop Linux/Windows release artifacts cannot be built or validated on this host due to missing toolchain and runtime dependencies. License notice validation for desktop must happen on the target platform build host.
- Apple platform release artifacts require Xcode and macOS host validation.
