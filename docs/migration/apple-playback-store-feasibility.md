# Apple Playback and Store Feasibility

This spike proves the Apple playback strategy for the Flutter rewrite at the
contract/documentation layer before native plugin work starts. The safe product
shape is an AVKit/AVPlayer-safe default for macOS, iOS, and iPadOS HLS/MP4
playback. MPVKit/libmpv remains GATED behind licensing, App Store policy,
crash/runtime review, native dependency review, and legal review. tvOS remains
BLOCKED/GATED until a community/custom embedder proof, plugin audit, and remote
input proof exist. Apple platforms stay non-blocking for the Desktop+Android
release track.

## Evidence used

- TDD baseline: `.omo/evidence/task-9-initial-failing-tests.txt` captures the
  first failing `flutter test test/playback/apple_backend_test.dart` run before
  `apple_backend_feasibility.dart` existed.
- Existing crash-risk reference:
  `modules/react-native-mpv/ios/MpvPlayerView.swift` already shows the hard
  parts of mpv on Apple: mpv calls are isolated on `mpvQueue`, UIKit/Metal work
  returns to the main thread, track reads are deferred to avoid mpv event-lock
  deadlocks, and render cleanup must drain before `mpv_render_context_free`.
- Existing MPVKit pod reference: `plugins/withMpvPlayer.js` injects a local
  `MPVKit.podspec`, downloads `MPVKit-GPL-Frameworks.zip`, marks MPVKit as
  `GPL-3.0`, and sets both iOS and tvOS deployment targets to 13.0.
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
| iOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | AVKit/AVPlayer-safe default for HLS/MP4, then server transcode. | MPVKit/libmpv only after approval gates. | Flutter can generate iOS projects, but App Store readiness is not claimed. |
| iPadOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | AVKit/AVPlayer-safe default for HLS/MP4, then server transcode. | MPVKit/libmpv only after approval gates. | Uses the supported iOS Flutter target; full-screen and iPad idiom QA remain gated. |
| macOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | AVKit/AVPlayer-safe default for HLS/MP4, then server transcode. | libmpv or MPVKit-equivalent only after approval gates. | Flutter macOS is supported, but signing, notarization, sandbox, and broad-codec playback are not release-complete. |
| tvOS | FAIL | BLOCKED/GATED | No release backend can be claimed yet. | AVKit/AVPlayer after a custom runner exists, then server transcode. | tvOS remains BLOCKED/GATED and is not release-complete until Flutter tvOS embedder, plugin, store, and remote QA proof exist. |

## Playback fallback matrix

| Target | Backend order | Why |
| --- | --- | --- |
| iOS | AVKit/AVPlayer-safe default, server transcode, optional gated MPVKit/libmpv | AVPlayer is the App Store-safe path for HLS/MP4. MPVKit covers more containers/codecs/subtitles only if every gate closes. |
| iPadOS | AVKit/AVPlayer-safe default, server transcode, optional gated MPVKit/libmpv | Same as iOS; iPad-specific work is layout and accessory input, not a separate decoder stack. |
| macOS | AVKit/AVPlayer-safe default, server transcode, optional gated libmpv or MPVKit-equivalent | AVPlayerView is the safe default when libmpv is unavailable, policy-blocked, unnecessary for HLS/MP4, or not legally approved. |
| tvOS | BLOCKED/GATED until custom/community embedder proof, then AVKit/AVPlayer first | This order is a native-design target only. Flutter cannot claim it until the tvOS embedder, plugins, and remote bridge run on simulator/hardware. |

AVKit/AVPlayer fallback is mandatory on every Apple target. For macOS, iOS, and
iPadOS, the release-safe default is AVKit/AVPlayer first for HLS/MP4, followed
by server-transcoded HLS when native paths reject the stream. Apple playback
must not be blocked on mpv, MPVKit, libmpv, or FFmpeg.

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
| Public APIs | App Store Review Guideline 2.5.1 | Use only AVKit, AVFoundation, UIKit/AppKit, Metal, VideoToolbox, GameController, and documented Flutter embedding APIs in release builds. | PASS for AVKit path; MPVKit/libmpv path remains GATED by plugin implementation review, App Store policy, and legal review. |
| Self-contained bundle | Guidelines 2.4.5 and 2.5.2 | All frameworks, dylibs, codec libraries, subtitle libraries, and Flutter artifacts are embedded and signed inside the app bundle; no shared install locations. | PASS for planned AVKit path; MPVKit/libmpv requires bundle audit. |
| No dynamic executable downloads | Guideline 2.5.2 | The app may stream media but must not download codecs, filters, native plugins, or executable code after review. | PASS if server transcode returns media only. |
| App completeness/crashes | Guideline 2.1 | Native playback must be tested on-device/simulator, with no mpv event-loop deadlocks or teardown crashes. | FAIL until native Flutter plugins are implemented and exercised. |
| Apple TV input | Guideline 2.4.3 | tvOS app works with Siri Remote and optional disclosed controllers. | FAIL/BLOCKED until custom embedder forwards remote/gamepad input. |
| macOS sandbox/package | Guideline 2.4.5 | Mac App Store build is sandboxed, Xcode-packaged, self-contained, and does not spawn unbundled helpers. | PASS for AVKit-only concept; libmpv requires sandbox entitlement and helper-process audit. |

Signing/bundle requirements:

- iOS/iPadOS/tvOS native frameworks must be embedded in the app target and
  code-signed by Xcode with valid provisioning profiles.
- macOS libmpv, FFmpeg, libass, and dependent libraries must live inside the
  `.app` bundle and pass sandbox/hardened-runtime/notarization checks for the
  selected distribution channel.
- MPVKit xcframework slices must match the target platform and simulator/device
  architectures; the current Expo podspec excludes problematic simulator archs.
- Do not ship separate codec installers, post-review framework downloads, or
  unbundled helper binaries.

## Licensing obligations and shipping decision

| Component | License signal | Obligations | Shipping decision |
| --- | --- | --- | --- |
| mpv | GPL-2.0-or-later by default, with possible LGPL-only build modes depending on configuration. | Publish corresponding source/notices for GPL builds, or prove and document an LGPL-only configuration with relink rights before distribution. | Feasibility only until legal approves a compatible binary strategy. |
| FFmpeg | LGPL/GPL configuration-dependent; nonfree combinations are not redistributable. | Record exact configure flags, enabled codecs, external libraries, source offers, and relink path. GPL/nonfree codec choices can make App Store distribution impossible for this app. | Prefer AVKit on Apple; bundle FFmpeg only after legal approves the exact build. |
| MPVKit | Current local podspec in `plugins/withMpvPlayer.js` declares GPL-3.0 and downloads `MPVKit-GPL-Frameworks.zip`. | GPL-3.0 requires compatible licensing for the combined distributed app plus corresponding source. | Do not ship MPVKit in production without an explicit GPL-compatible app licensing decision. |
| libass | ISC permissive license. | Preserve copyright/license notices when bundled directly or through mpv/FFmpeg. | Acceptable as a dependency, but combined binaries inherit mpv/FFmpeg obligations. |
| Plezy reference code | GPL reference material. | Do not copy source unless this project accepts GPL-compatible licensing for derived work. | Conceptual reference only; use architecture lessons, not code. |

The current product-safe Apple path is AVKit/AVPlayer plus server transcode.
MPVKit/libmpv remains GATED for parity and codec research only. It is not an
App Store shipping commitment until GPL/LGPL posture, exact FFmpeg flags, source
offer duties, signing, App Store policy, crash/runtime review, native dependency
review, and legal review are closed.

## Next technical steps

1. Implement a Flutter Apple playback plugin API that selects AVPlayer first for
   HLS/MP4, then optionally MPVKit/libmpv for approved broad-codec sources, then
   server transcode.
2. Build iOS/iPadOS and macOS native plugin spikes on a macOS/Xcode host and add
   simulator/device smoke tests for load/play/pause/seek/teardown.
3. Prototype a custom Flutter tvOS embedder with AVPlayer playback only, then add
   `GCController` and Siri Remote press forwarding before attempting MPVKit.
4. Produce a legal bill of materials for any mpv/FFmpeg/MPVKit/libass binary and
   make the GPL/LGPL/App Store distribution decision before shipping.
