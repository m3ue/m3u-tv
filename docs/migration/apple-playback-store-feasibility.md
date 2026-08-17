# Apple Playback and Store Feasibility

> **Status update -- the "MPVKit/libmpv not planned" decisions throughout this
> document are superseded.** This spike's central blocker for iOS/iPadOS/tvOS
> was that MPVKit's GPL-3.0 posture was judged incompatible with this app's
> (then non-GPL) App Store distribution. **This project has since relicensed
> to GPL-3.0** (see repository root `LICENSE` and
> `docs/release/license-notices-checklist.md`), which removes that blocker.
> Native mpv playback (via the `edde746/MPVKit` Swift package, modeled on the
> open-source [Plezy](https://github.com/edde746/plezy) player, same author,
> GPL-3.0) is now the **primary, working playback backend on all three Apple
> platforms** (macOS, iOS, and tvOS), not just the media_kit/AVKit paths
> this document describes as permanent. Native mpv is confirmed fully working
> (video, audio, subtitles, track switching, seeking, clean back-navigation
> teardown) on macOS and iOS via hands-on click-testing, and playback (video,
> audio, subtitles) works correctly on tvOS too, with one known open cosmetic
> bug: the playback overlay renders "boxed in", smaller than the video behind
> it. `media_kit` (`MediaKitIosAdapter`/`MediaKitDesktopAdapter`) has been
> removed from the main-playback fallback chain on iOS and macOS; only
> `AppleAvKitBackend` remains as an automatic fallback (iOS/tvOS only --
> macOS currently has no automatic fallback). `media_kit` is no longer used
> anywhere on macOS: the separate Multiview surface now also uses
> `MacMpvNativeBackend`. This document's App Store guideline analysis (2.4.3, 2.4.5, 2.5.1,
> 2.5.2), tvOS embedder/remote-input findings, and AVKit-as-fallback design
> remain valid and relevant -- only the "MPVKit is not planned, GPL blocks it"
> conclusion is out of date. App Store submission readiness itself (signing,
> notarization, TestFlight, a follow-up legal/App Store review pass
> specifically for GPL-3.0 distribution -- source-offer obligations, App
> Store Review Guideline 2.5.1's stance on GPL binaries, etc.) has not yet
> been attempted and should happen before shipping mpv-based builds to the
> App Store.

This spike originally proved the Apple playback strategy for the Flutter
rewrite at the contract/documentation layer before native plugin work
started, with AVKit/AVPlayer as the safe default for iOS/iPadOS and
media_kit for macOS, and MPVKit/libmpv gated behind licensing and App Store
policy review. That plan has since been superseded: the project relicensed
to GPL-3.0 specifically to unblock bundling MPVKit, and native mpv (via
`edde746/MPVKit`) is now the working primary playback backend on macOS, iOS,
and tvOS, with AVKit/AVPlayer demoted to an automatic fallback (iOS/tvOS
only) rather than the primary path, and media_kit removed entirely, from
macOS Multiview too (see the status callout above). tvOS playback itself works
(video, audio, subtitles); the tvOS Flutter embedder/build/remote-input
findings below remain accurate as historical/reference context for how the
tvOS runner was built, but should not be read as still gating playback
availability. Apple platforms stay non-blocking for the Desktop+Android
release track. App Store distribution readiness (signing, notarization,
submission review) has not yet been verified for the mpv-based builds.

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
| iOS | PASS for Flutter project generation | WORKING -- confirmed via click-testing on iOS Simulator | Native mpv (`edde746/MPVKit`, `PlaybackBackend.appleMpvNative`), confirmed working (video, audio, no crash on back navigation). | `AppleAvKitBackend` as the sole automatic fallback if native mpv throws. | Native mpv is the primary, working playback strategy on iOS. App Store submission readiness (signing, notarization, review) is not yet verified. |
| iPadOS | PASS for Flutter project generation | WORKING (shares the iOS target) | Same as iOS: native mpv primary, `AppleAvKitBackend` fallback. | `AppleAvKitBackend`. | Uses the supported iOS Flutter target; iPad-specific idiom/full-screen QA is separate from the backend question and remains untracked here. |
| macOS | PASS for Flutter project generation | WORKING -- confirmed via click-testing | Native mpv (`edde746/MPVKit`, `PlaybackBackend.macMpvNative`), confirmed working (video, audio, subtitles, track switching, seeking, clean teardown). | None for main playback currently -- `MediaKitDesktopAdapter` was removed as a fallback and is no longer used anywhere on macOS, including for Multiview (now also on `MacMpvNativeBackend`). | Native mpv is the primary, working playback strategy on macOS. Signing, notarization, and sandbox readiness for App Store distribution are not release-complete. |
| tvOS | Builds via a custom Xcode-based runner (no `flutter build tvos` CLI support) | WORKING -- video, audio, subtitles all confirmed correct | Native mpv (`edde746/MPVKit`, `PlaybackBackend.appleMpvNative`), same as iOS. | `AppleAvKitBackend`. | tvOS playback works. The overlay-scaling cosmetic bug (playback overlay rendering "boxed in" relative to the video) has been fixed. App Store/TestFlight submission readiness is not yet verified. |

## Playback fallback matrix

| Target | Backend order | Why |
| --- | --- | --- |
| iOS | Native mpv (`appleMpvNative`), then `AppleAvKitBackend`, then server transcode | Native mpv (`edde746/MPVKit`) is the working primary backend, confirmed via click-testing; GPL-3.0 relicensing removed the prior App Store blocker. AVKit remains the automatic fallback if native mpv throws. |
| iPadOS | Same as iOS | Shares the iOS target; iPad-specific work is layout and accessory input, not a separate decoder stack. |
| macOS | Native mpv (`macMpvNative`), then server transcode | Native mpv is the working primary backend, confirmed via click-testing. No automatic native fallback currently exists for main playback (media_kit was removed from that role entirely, including for Multiview). |
| tvOS | Native mpv (`appleMpvNative`), then `AppleAvKitBackend`, then server transcode | Playback (video/audio/subtitles) works; the overlay-scaling cosmetic bug (overlay "boxed in" relative to the video) has been fixed. The custom Xcode-based tvOS runner referenced below is already in place and building. |

Native mpv is the primary backend on all three Apple platforms.
`AppleAvKitBackend` remains the mandatory automatic fallback on iOS/tvOS if
native mpv throws a recoverable `PlaybackException`; macOS currently has no
automatic fallback for main playback. Server-transcoded HLS is the final
fallback everywhere when native paths reject the stream. Apple playback is
no longer blocked on MPVKit/libmpv licensing -- the GPL-3.0 relicense
removed that blocker.

## tvOS build, embedder, focus, and remote decision

Current status: build and playback now work via a custom Xcode-managed
`tvos/Runner.xcodeproj` runner (see `mpv-native-apple-setup.md`), with
native mpv playback confirmed (video, audio, subtitles correct; one open
cosmetic overlay-scaling bug). Store/App-Store-submission proof is still
GATED and tvOS is not release-complete for that purpose.

- Flutter tvOS is still not an official first-class target in the pinned
  toolchain -- the CLI platform generation help lists iOS/macOS/darwin but
  no tvOS, and the build command surface does not provide `flutter build
  tvos`. The app instead builds through a manually-wired Xcode project (see
  `mpv-native-apple-setup.md`), which is the path actually in use today.
- The custom runner already hosts the Flutter engine/view, loads the tvOS
  plugin registrar, and packages/signs through Xcode -- this is done, not
  merely planned.
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
| Public APIs | App Store Review Guideline 2.5.1 | Use only AVKit, AVFoundation, UIKit/AppKit, Metal, VideoToolbox, GameController, and documented Flutter embedding APIs in release builds. | Native mpv (MPVKit, GPL-3.0) is now the primary path on iOS/iPadOS/tvOS/macOS, with AVKit as an automatic fallback (iOS/tvOS). A dedicated legal/App Store review pass on GPL-3.0 binary distribution under 2.5.1 has not yet been done -- see the licensing obligations table below. |
| Self-contained bundle | Guidelines 2.4.5 and 2.5.2 | All frameworks, dylibs, codec libraries, subtitle libraries, and Flutter artifacts are embedded and signed inside the app bundle; no shared install locations. | MPVKit is added as an SPM dependency embedded in the Runner targets (see `mpv-native-apple-setup.md`); bundle/signing verification for App Store distribution has not yet been done. |
| No dynamic executable downloads | Guideline 2.5.2 | The app may stream media but must not download codecs, filters, native plugins, or executable code after review. | PASS if server transcode returns media only; native mpv/MPVKit is statically embedded at build time, not downloaded at runtime. |
| App completeness/crashes | Guideline 2.1 | Native playback must be tested on-device/simulator, with no mpv event-loop deadlocks or teardown crashes. | Confirmed via hands-on click-testing on macOS and iOS Simulator: no crashes, clean teardown on back navigation. tvOS playback is also crash-free; still needs verification on real Apple TV hardware, not just simulator/dev builds. |
| Apple TV input | Guideline 2.4.3 | tvOS app works with Siri Remote and optional disclosed controllers. | The app is D-pad/Siri-Remote-driven via the `dpad` package throughout; dedicated remote-input App Store review proof has not been separately re-verified in this doc. |
| macOS sandbox/package | Guideline 2.4.5 | Mac App Store build is sandboxed, Xcode-packaged, self-contained, and does not spawn unbundled helpers. | Native mpv (MPVKit) is the primary macOS path now; sandbox/hardened-runtime/notarization verification for a GPL-3.0 native library has not yet been done. |

Signing/bundle requirements:

- iOS/iPadOS/tvOS/macOS native frameworks (including the `edde746/MPVKit`
  SPM package) must be embedded in the app target and code-signed by Xcode
  with valid provisioning profiles.
- Native mpv/MPVKit ships GPL-3.0 code on all four Apple targets now; the
  media_kit dependencies previously used as the macOS default are no
  longer used at all, including for macOS Multiview. Sandbox/hardened-
  runtime/notarization checks for the MPVKit-based bundle have not yet
  been run for any distribution channel.
- The xcframework-slice/architecture notes historically kept here as
  reference from the old Expo/React Native podspec remain reference-only
  context for how MPVKit frameworks are structured.
- Do not ship separate codec installers, post-review framework downloads, or
  unbundled helper binaries.

## Licensing obligations and shipping decision

| Component | License signal | Obligations | Shipping decision |
| --- | --- | --- | --- |
| mpv | GPL-2.0-or-later by default, with possible LGPL-only build modes depending on configuration. | Publish corresponding source/notices for GPL builds, or prove and document an LGPL-only configuration with relink rights before distribution. | Now shipping on iOS/iPadOS/tvOS/macOS as the primary playback path via MPVKit. These obligations are actually applicable now, not hypothetical -- see `docs/release/license-notices-checklist.md`. |
| FFmpeg | LGPL/GPL configuration-dependent; nonfree combinations are not redistributable. | Record exact configure flags, enabled codecs, external libraries, source offers, and relink path. GPL/nonfree codec choices can make App Store distribution impossible for this app. | Bundled transitively via MPVKit on all Apple targets now. The project relicensed to GPL-3.0 specifically to allow this; exact configure-flag/source-offer documentation still needs to be finalized before an App Store submission. |
| MPVKit | The former RN podspec (now removed) declared GPL-3.0 and downloaded `MPVKit-GPL-Frameworks.zip`. The current Flutter integration uses the `edde746/MPVKit` Swift Package Manager fork (GPL-3.0), added per-target in Xcode (see `mpv-native-apple-setup.md`). | GPL-3.0 requires compatible licensing for the combined distributed app plus corresponding source. | Actively shipping on iOS/iPadOS/tvOS/macOS as the primary backend. The project's GPL-3.0 relicense (repo root `LICENSE`) satisfies the combined-licensing requirement; a dedicated App Store review pass for GPL-3.0 binary distribution has not yet been done. |
| libass | ISC permissive license. | Preserve copyright/license notices when bundled directly or through mpv/FFmpeg. | Acceptable as a dependency, but combined binaries inherit mpv/FFmpeg obligations. |
| Plezy reference code | GPL reference material. | Do not copy source unless this project accepts GPL-compatible licensing for derived work. | Conceptual reference only; no Plezy source is copied into this repository. The GPL-3.0 relicense makes such GPL-compatible licensing moot as a blocker either way. |

The current product path is native mpv (MPVKit) plus AVKit fallback and
server transcode on iOS/iPadOS/tvOS, and native mpv plus server transcode on
macOS (no automatic native fallback there yet). This is a change from the
prior plan of AVKit/media_kit as the permanent strategy: MPVKit/libmpv is no
longer blocked by GPL-3.0 incompatibility with App Store distribution, since
the project relicensed to GPL-3.0 specifically to unblock it. What remains
open is verifying actual App Store submission readiness (notarization,
TestFlight, review) for the GPL-3.0 binary, not the playback backend choice
itself.

## Next technical steps

1. Native mpv playback plugins are implemented and confirmed working on
   iOS/iPadOS (click-tested on iOS Simulator), macOS (click-tested), and
   tvOS (video/audio/subtitles correct). The remaining work here is App
   Store submission readiness, not the backend implementation itself:
   verify signing, notarization, and GPL-3.0 source-offer/notice
   obligations before submitting mpv-based builds for review.
2. The tvOS overlay-scaling cosmetic bug (playback overlay renders
   "boxed in" relative to the video) has been fixed.
3. The macOS Multiview regression has been fixed: `buildMultiviewTilePlayer()`
   now uses `MacMpvNativeBackend` (which implements `MultiviewBackend`)
   instead of `MediaKitDesktopAdapter`.
4. Produce a legal bill of materials for the mpv/FFmpeg/MPVKit/libass
   binaries now actually shipping, and complete GPL-3.0 App Store
   submission review (source-offer obligations, notarization, TestFlight)
   before submitting mpv-based builds for review.
