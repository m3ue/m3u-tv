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
- **Scope**: Linux and Windows desktop in-process playback.
- **License**: LGPL-2.1+ (libmpv client library). The mpv core contains GPL-2.0+ components.
- **Notice requirement**: If libmpv is linked dynamically, include LGPL notices and provide a written offer for the source if distributing binaries. If linked statically or if GPL-only components are included, the entire artifact may become GPL-derived.
- **Status**: Future-gated for Android; active for Linux/Windows desktop only where libmpv is packaged.
- **Gate**: Do not ship GPL-only binaries or GPL-derived code in a store/direct-download artifact unless the release owner explicitly accepts GPL distribution obligations and records that decision in release evidence.

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

## Apple Playback Dependencies (Future-Gated)

### AVKit / AVPlayer
- **Scope**: iOS, iPadOS, macOS, and tvOS playback fallback.
- **License**: Apple proprietary framework; no additional third-party notice required beyond Apple standard terms.
- **Status**: Safe fallback path for Apple platforms.
- **Gate**: No additional license gate beyond standard Apple distribution terms.

### MPVKit (Blocked)
- **Scope**: Broad-codec Apple playback via MPVKit framework.
- **License**: GPL/LGPL (same as mpv/libmpv).
- **Status**: Blocked until GPL/LGPL/FFmpeg, signing, and crash-review gates pass.
- **Gate**: Do not ship MPVKit in a store artifact without explicit GPL acceptance and license review evidence.

## GPL Policy Gate

- **Rule**: Do not ship GPL-only binaries, GPL-derived code, or Plezy reference code in a store/direct-download artifact unless the release owner explicitly accepts the GPL distribution obligations and records that decision in release evidence.
- **Scope**: This applies to mpv core, GPL-enabled FFmpeg builds, and any statically linked GPL components.
- **Safe path**: Media3/ExoPlayer on Android, AVKit on Apple, and dynamically linked LGPL libmpv on desktop (with proper notices and source offer) are the safe default paths.
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
- Desktop Linux/Windows release artifacts cannot be built or validated on this host due to missing toolchain and runtime dependencies. License notice validation for desktop must happen on the target platform build host.
- Apple platform release artifacts require Xcode and macOS host validation.
