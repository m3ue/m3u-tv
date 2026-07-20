# Apple Playback and Store Feasibility

This spike proves the Apple playback strategy for the Flutter rewrite at the
contract/documentation layer before native plugin work starts. The safe product
shape is an AVKit/AVPlayer-safe default for iOS and iPadOS HLS/MP4 playback,
and media_kit (AVFoundation-backed) for macOS. MPVKit/libmpv remains GATED
behind licensing, App Store policy, crash/runtime review, native dependency review,
and legal review for iOS/iPadOS; it is not planned for macOS — a
native in-process libmpv backend was prototyped there and reverted once
media_kit was confirmed to already work correctly. tvOS remains
BLOCKED/GATED until a community/custom embedder proof, plugin audit, and remote
input proof exist. Apple platforms stay non-blocking for the Desktop+Android
release track.

## Evidence used

- TDD baseline: `.omo/evidence/task-9-initial-failing-tests.txt` captures the
  first failing `flutter test test/playback/apple_backend_test.dart` run before
  `apple_backend_feasibility.dart` existed.
- Prior RN crash-risk evidence (files removed): The former
  `modules/react-native-mpv/ios/MpvPlayerView.swift` demonstrated the key mpv
  Apple hazards: mpv calls isolated on `mpvQueue`, UIKit/Metal work returning to
  the main thread, deferred track reads to avoid mpv event-lock deadlocks, and
  render cleanup draining before `mpv_render_context_free`. These patterns inform
  the Flutter plugin design even though the RN source no longer exists.
- Prior MPVKit pod reference (file removed): The former `plugins/withMpvPlayer.js`
  injected a local `MPVKit.podspec`, downloaded `MPVKit-GPL-Frameworks.zip`,
  marked MPVKit as `GPL-3.0`, and set iOS and tvOS deployment targets to 13.0.
  Both files were deleted with the React Native app removal.
- Flutter CLI validation on this Linux host:
  `/tmp/flutter/bin/flutter create --help` lists `ios`, `macos`, and shared
  `darwin` plugin generation, but no `tvos`; `/tmp/flutter/bin/flutter build
  tvos --help` does not expose a tvOS build subcommand.
- Apple App Review constraints checked from
  `https://developer.apple.com/app-store/review/guidelines/`, especially 2.4.3,
  2.4.5, 2.5.1, and 2.5.2.
- Plezy macOS/iOS/tvOS references are treated as conceptual GPL reference
  material only. No Plezy source code is copied into this repository.

## Build/playback gate matrix

| Platform | Build | Playback | Primary backend | Required fallback | Decision |
| --- | --- | --- | --- | --- | --- |
| iOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | AVKit/AVPlayer-safe default for HLS/MP4, then server transcode. | MPVKit/libmpv not planned — GPL-3.0 distribution is incompatible with App Store review, so this app cannot list with it bundled. | Flutter can generate iOS projects, but App Store readiness is not claimed. AVKit/AVPlayer is the permanent playback strategy, not an interim step pending MPVKit approval. |
| iPadOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | AVKit/AVPlayer-safe default for HLS/MP4, then server transcode. | MPVKit/libmpv not planned — same GPL/App Store incompatibility as iOS. | Uses the supported iOS Flutter target; full-screen and iPad idiom QA remain gated. |
| macOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | media_kit (AVFoundation-backed), then server transcode. | None planned — a native in-process libmpv backend was prototyped and reverted; media_kit already covers macOS well. | Flutter macOS is supported, but signing, notarization, and sandbox are not release-complete. Broad-codec playback via libmpv/MPVKit is not planned for this platform. |
| tvOS | FAIL | BLOCKED/GATED | No release backend can be claimed yet. | AVKit/AVPlayer after a custom runner exists, then server transcode. MPVKit/libmpv not planned — same GPL/App Store incompatibility as iOS, independent of the embedder blocker below. | tvOS remains BLOCKED/GATED and is not release-complete until Flutter tvOS embedder, plugin, store, and remote QA proof exist. |

## Playback fallback matrix

| Target | Backend order | Why |
| --- | --- | --- |
| iOS | AVKit/AVPlayer-safe default, server transcode | AVPlayer is the App Store-safe path for HLS/MP4 and the permanent strategy. MPVKit/libmpv is not planned — GPL-3.0 cannot be reconciled with App Store distribution for this app. |
| iPadOS | AVKit/AVPlayer-safe default, server transcode | Same as iOS; iPad-specific work is layout and accessory input, not a separate decoder stack. MPVKit/libmpv not planned for the same GPL/App Store reason. |
| macOS | media_kit (AVFoundation-backed), server transcode | media_kit is the default and only planned backend; libmpv/MPVKit is not planned for macOS after prototyping confirmed media_kit already handles it well. |
| tvOS | BLOCKED/GATED until custom/community embedder proof, then AVKit/AVPlayer first | This order is a native-design target only. Flutter cannot claim it until the tvOS embedder, plugins, and remote bridge run on simulator/hardware. MPVKit/libmpv is not planned regardless, for the same GPL/App Store reason as iOS. |

AVKit/AVPlayer fallback is mandatory on every iOS/iPadOS/tvOS target; the
release-safe default there is AVKit/AVPlayer first for HLS/MP4, followed by
server-transcoded HLS when native paths reject the stream. macOS uses
media_kit as its default and only planned backend. Apple playback must not be
blocked on mpv, MPVKit, libmpv, or FFmpeg.

## tvOS build, embedder, focus, and remote decision

Current status: FAIL for Flutter build/playback and BLOCKED/GATED for remote,
plugin, store, and custom embedder proof. tvOS is not release-complete.

- Flutter tvOS is not an official first-class target in the pinned toolchain.
  The CLI platform generation help lists iOS/macOS/darwin but no tvOS, and the
  build command surface does not provide `flutter build tvos`.
- A custom Flutter tvOS embedder is required before app-level feasibility can be
  upgraded. The embedder must create a tvOS `UIApplication`, host the Flutter
  engine/view, load a tvOS plugin registrar, and package/sign the runner through
  Xcode.
- Remote/gamepad handling cannot be marked PASS yet. The next technical step is
  to prototype `pressesBegan`/`pressesEnded` and `GCController` forwarding in
  the custom Flutter tvOS embedder, then map Siri Remote select/menu/play-pause
  and D-pad/gamepad events into Flutter focus and playback actions.
- App Store Review Guideline 2.4.3 requires Apple TV apps to work without
  hardware inputs beyond the Siri Remote or disclosed game controllers. Do not
  require a game controller unless metadata states that requirement.

## tvOS plugin audit checklist

Before any tvOS release claim, audit each Flutter and native plugin for these
items:

- Platform detection must distinguish Platform.isIOS vs tvOS behavior. A plugin
  that treats tvOS as generic iOS is not approved until runner, registrar, and
  input behavior are proven.
- missing tvOS plugin implementations must be listed with owner, replacement, or
  removal decision. iOS-only plugins do not count as tvOS support.
- Store/legal review must cover App Store policy, privacy strings, codec use,
  GPL and LGPL obligations, FFmpeg configuration, MPVKit packaging, and source
  offer duties.
- Community/custom embedder proof must include the exact Flutter tvOS fork or
  custom embedder revision, a signed runner build, plugin registrar proof, Siri
  Remote input proof, and playback smoke evidence.


## App Store, signing, bundle, and public API gates

| Gate | Relevant guideline | PASS condition | Current result |
| --- | --- | --- | --- |
| Public APIs | App Store Review Guideline 2.5.1 | Use only AVKit, AVFoundation, UIKit/AppKit, Metal, VideoToolbox, GameController, and documented Flutter embedding APIs in release builds. | PASS for the AVKit path (the only planned iOS/iPadOS/tvOS path). MPVKit/libmpv is not planned — its GPL-3.0 posture is incompatible with App Store distribution for this app. |
| Self-contained bundle | Guidelines 2.4.5 and 2.5.2 | All frameworks, dylibs, codec libraries, subtitle libraries, and Flutter artifacts are embedded and signed inside the app bundle; no shared install locations. | PASS for the planned AVKit path; not applicable to MPVKit/libmpv since it is not planned. |
| No dynamic executable downloads | Guideline 2.5.2 | The app may stream media but must not download codecs, filters, native plugins, or executable code after review. | PASS if server transcode returns media only. |
| App completeness/crashes | Guideline 2.1 | Native playback must be tested on-device/simulator, with no mpv event-loop deadlocks or teardown crashes. | FAIL until native Flutter plugins are implemented and exercised. |
| Apple TV input | Guideline 2.4.3 | tvOS app works with Siri Remote and optional disclosed controllers. | FAIL/BLOCKED until custom embedder forwards remote/gamepad input. |
| macOS sandbox/package | Guideline 2.4.5 | Mac App Store build is sandboxed, Xcode-packaged, self-contained, and does not spawn unbundled helpers. | PASS for the media_kit path. libmpv is not planned for macOS, so its sandbox/helper-process gate does not apply here. |

Signing/bundle requirements:

- iOS/iPadOS/tvOS native frameworks must be embedded in the app target and
  code-signed by Xcode with valid provisioning profiles.
- libmpv/FFmpeg/libass are not planned for macOS; the media_kit dependencies it
  already ships with must live inside the `.app` bundle and pass
  sandbox/hardened-runtime/notarization checks for the selected distribution
  channel.
- MPVKit is not planned for iOS/tvOS (GPL-3.0 is incompatible with App Store
  distribution for this app); the xcframework-slice/architecture notes below
  are kept only as historical reference from the Expo/React Native podspec.
- Do not ship separate codec installers, post-review framework downloads, or
  unbundled helper binaries.

## Licensing obligations and shipping decision

| Component | License signal | Obligations | Shipping decision |
| --- | --- | --- | --- |
| mpv | GPL-2.0-or-later by default, with possible LGPL-only build modes depending on configuration. | Publish corresponding source/notices for GPL builds, or prove and document an LGPL-only configuration with relink rights before distribution. | Not planned for iOS/iPadOS/tvOS — AVKit/AVPlayer is the permanent strategy there. Kept as reference material only. |
| FFmpeg | LGPL/GPL configuration-dependent; nonfree combinations are not redistributable. | Record exact configure flags, enabled codecs, external libraries, source offers, and relink path. GPL/nonfree codec choices can make App Store distribution impossible for this app. | Not planned for iOS/iPadOS/tvOS; AVKit is used instead. |
| MPVKit | The former RN podspec (now removed) declared GPL-3.0 and downloaded `MPVKit-GPL-Frameworks.zip`. Any Flutter equivalent must make the same declaration. | GPL-3.0 requires compatible licensing for the combined distributed app plus corresponding source. | Not planned for iOS/iPadOS/tvOS — GPL-3.0 is incompatible with App Store distribution for this app, not a to-be-resolved review gate. |
| libass | ISC permissive license. | Preserve copyright/license notices when bundled directly or through mpv/FFmpeg. | Acceptable as a dependency, but combined binaries inherit mpv/FFmpeg obligations. |
| Plezy reference code | GPL reference material. | Do not copy source unless this project accepts GPL-compatible licensing for derived work. | Conceptual reference only; use architecture lessons, not code. |

The current product-safe path is AVKit/AVPlayer plus server transcode on
iOS/iPadOS/tvOS, and media_kit plus server transcode on macOS. MPVKit/libmpv
is not planned for any Apple platform: on iOS/iPadOS/tvOS it is blocked by
GPL-3.0's incompatibility with App Store distribution (a firm decision, not
a review gate awaiting approval), and on macOS media_kit was prototyped
against and already covers what libmpv would have provided.

## Next technical steps

1. Implement a Flutter iOS/iPadOS playback plugin API that selects AVPlayer
   for HLS/MP4, then server transcode. MPVKit/libmpv is not planned — do not
   build a licensing-gated fallback path for it. macOS uses media_kit and
   needs no equivalent plugin work.
2. Build iOS/iPadOS native plugin spikes on a macOS/Xcode host and add
   simulator/device smoke tests for load/play/pause/seek/teardown.
3. Prototype a custom Flutter tvOS embedder with AVPlayer playback only, then
   add `GCController` and Siri Remote press forwarding. MPVKit is not planned
   for tvOS either.
4. If the MPVKit/App Store decision is ever revisited, produce a legal bill of
   materials for any mpv/FFmpeg/MPVKit/libass binary first — this is not
   currently planned work.
