# License Notices Checklist

This document records the third-party dependency license notices that must be included with every distributed artifact (Play Store, App Store, Microsoft Store, sideload, or direct download). It is a release gate: no public distribution is complete until the matching notices are reviewed, generated, and saved with the signed artifact evidence.

## App License

- The M3U TV Flutter client is licensed under **CC BY-NC-SA 4.0**.
- The full license text is available at the repository root: `LICENSE`.
- Attribution, non-commercial, and share-allike obligations apply to all distributed artifacts.

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

## Desktop Playback Dependencies (Future-Gated)

### mpv / libmpv
- **Scope**: Linux, Windows, and macOS desktop in-process playback. macOS bundles the MPVKit framework (see below) rather than the system/dlopen'd libmpv Linux uses or the plain DLL Windows bundles.
- **License**: LGPL-2.1+ (libmpv client library). The mpv core contains GPL-2.0+ components.
- **Notice requirement**: If libmpv is linked dynamically, include LGPL notices and provide a written offer for the source if distributing binaries. If linked statically or if GPL-only components are included, the entire artifact may become GPL-derived.
- **Status**: Future-gated for Android; active for Linux/Windows/macOS desktop where libmpv is packaged.
- **Gate**: Do not ship GPL-only binaries or GPL-derived code in a store/direct-download artifact unless the release owner explicitly accepts GPL distribution obligations and records that decision in release evidence. On macOS, MPVKit itself is GPL-3.0 (see "MPVKit" below) — accepted for this app's direct-to-GitHub DMG distribution, since it is not published through the Mac App Store.

### FFmpeg
- **Scope**: Bundled with libmpv on Linux/Windows desktop, and with MPVKit on macOS.
- **License**: LGPL-2.1+ or GPL-2.0+ depending on build configuration (codecs, filters, and protocols enabled).
- **Notice requirement**: Include FFmpeg license notices. If using GPL-enabled FFmpeg build, the same GPL policy as mpv applies.
- **Status**: Desktop-only, bundled as part of the libmpv/MPVKit runtime.
- **Gate**: Verify the exact FFmpeg build flags and license before distribution. GPL-enabled FFmpeg makes the artifact GPL-derived.

### libass
- **Scope**: Subtitle rendering in libmpv/MPVKit.
- **License**: ISC / BSD-style (libass itself). Some dependencies may have different licenses.
- **Notice requirement**: Include libass license notices in bundled desktop artifacts.
- **Status**: Desktop-only, bundled with libmpv/MPVKit.
- **Gate**: Verify libass and its dependency notices are present.

## Apple Playback Dependencies

### AVKit / AVPlayer
- **Scope**: iOS, iPadOS, and tvOS playback (permanent primary backend, not a fallback pending MPVKit approval). macOS uses a native libmpv/MPVKit backend instead — see the Desktop Playback Dependencies section.
- **License**: Apple proprietary framework; no additional third-party notice required beyond Apple standard terms.
- **Status**: Safe, permanent path for iOS/iPadOS/tvOS.
- **Gate**: No additional license gate beyond standard Apple distribution terms.

### MPVKit
- **Scope**: Broad-codec playback via the MPVKit framework, bundled into the macOS desktop `.app` (see Desktop Playback Dependencies → mpv / libmpv). **Not planned for iOS/tvOS** — GPL-3.0 is incompatible with Apple App Store distribution for this app, a firm decision rather than a pending review gate.
- **License**: GPL-3.0.
- **Status**: Active on macOS desktop only. Distribution is direct-to-GitHub-Release DMG, not the Mac App Store, so the GPL-3.0/App-Store-incompatibility concern that previously blocked this on macOS as well does not apply; the GPL Policy Gate below has been explicitly accepted for the macOS desktop artifact.
- **Gate**: Do not ship MPVKit in an App Store artifact (iOS/tvOS/Mac App Store) without explicit GPL acceptance and license review evidence — none is planned for those. macOS direct-download DMG distribution is the accepted GPL path; see GPL Policy Gate below.

## GPL Policy Gate

- **Rule**: Do not ship GPL-only binaries, GPL-derived code, or Plezy reference code in a store/direct-download artifact unless the release owner explicitly accepts the GPL distribution obligations and records that decision in release evidence.
- **Scope**: This applies to mpv core, GPL-enabled FFmpeg builds, MPVKit (GPL-3.0), and any statically linked GPL components.
- **Safe path**: Media3/ExoPlayer on Android and AVKit on iOS/iPadOS/tvOS are the safe default paths for those platforms (no store-compatibility question). Desktop (Linux/Windows/macOS) ships GPL-inclusive libmpv/MPVKit builds via direct-to-GitHub DMG/ZIP distribution — not any app store — which is the accepted path for this app's GPL Policy Gate decision.
- **Evidence requirement**: Any release that includes GPL components must have a signed-off license review document saved with the artifact evidence.

## Release Artifact Checklist

Before any store or sideload release, verify:

- [ ] `LICENSE` (CC BY-NC-SA 4.0) is included or referenced in the artifact metadata.
- [ ] Media3/ExoPlayer AndroidX notices are present (via `NOTICES.Z` or explicit third-party notices file).
- [ ] Flutter SDK and plugin notices are present (via `NOTICES.Z` or explicit third-party notices file).
- [ ] Desktop artifacts only: libmpv, FFmpeg, and libass notices are present and the exact license (LGPL vs GPL) is verified.
- [ ] Desktop artifacts only: a written offer for source code is included if LGPL components are distributed as binaries.
- [ ] No GPL-only components are included without explicit release-owner acceptance and evidence.
- [ ] All notices are saved with the signed artifact evidence under `.omo/evidence/` or equivalent release evidence directory.

## Honest Blockers

- License notice generation and review are not automated in this repository. Each platform release must manually verify the generated notices before distribution.
- Desktop Linux/Windows/macOS release artifacts cannot be built or validated on this host due to missing toolchain and runtime dependencies. License notice validation for desktop must happen on the target platform build host.
- Apple platform release artifacts require Xcode and macOS host validation.
