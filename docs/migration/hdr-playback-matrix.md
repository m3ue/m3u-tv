# HDR Playback Decision Matrix

This is the maintained phase-one HDR contract for current `upstream/dev`. It does not implement HDR playback and makes no HDR delivery claim from a codec, resolution, backend name, or marketing statement. The only outcome vocabulary is **verified**, **platform-contingent**, **unsupported**, and **unverified/blocker**. A format is verified only after the complete source, decoder, renderer, display, and real-device path is recorded here.

## Current facts and boundaries

`PlaybackCapabilities` has no HDR fields, and `PlaybackOrchestrator` has no HDR detection or output-state contract. Android selects the Media3 adapter; iOS and iPadOS select media_kit and AVKit; tvOS selects AVKit; macOS selects media_kit; Linux and Windows select the custom in-process libmpv backend. The source evidence is `flutter_client/lib/navigation/app_router.dart`, `flutter_client/lib/playback/playback_capabilities.dart`, and `flutter_client/lib/playback/playback_orchestrator.dart`.

The Android native plugin supplies an ExoPlayer through a Flutter texture. The iOS and tvOS AVKit plugins request 32-bit BGRA pixel buffers through `AVPlayerItemVideoOutput`; tvOS also requests Metal compatibility. Linux and Windows use libmpv `MPV_RENDER_API_TYPE_SW` and RGBA Flutter pixel-buffer textures. macOS uses media_kit's texture controller. These are rendering-path facts, not HDR metadata-preservation or display-output evidence.

PR #209 is pending Draft. Issue #167 is In review. Neither is current delivered HDR behavior.

## Output contract for future work

Future backend-independent state has exactly these normalized states:

- `source HDR detected`
- `HDR output active`
- `HDR tone-mapped to SDR`
- `HDR unsupported/unavailable`

Native events and diagnostics may contain only normalized non-sensitive transfer characteristics, color primaries, color space, and bit depth. They must not contain stream URLs, headers, credentials, tokens, or raw native payloads.

Server transcode is unverified and not HDR-capable until complete generated output and delivery path prove metadata preservation and renderer behavior. It inherits no HDR claim from the source.

## Decision summary

| Target | Backend and native path | HDR10 | HDR10+ | HLG | Dolby Vision | Metadata preservation | Tone mapping/fallback | Minimum prerequisites and packaging | Real device/runtime |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Android phone/tablet | Media3 ExoPlayer to Flutter texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | No app-specific HDR minimum or HDR packaging proof recorded | unverified/blocker |
| Android TV | Media3 ExoPlayer to Flutter texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | No app-specific HDR minimum or HDR packaging proof recorded | unverified/blocker |
| iOS | media_kit and AVKit via BGRA Flutter texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | No app-specific HDR minimum or App Store HDR packaging proof recorded | unverified/blocker |
| iPadOS | media_kit and AVKit via BGRA Flutter texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | No app-specific HDR minimum or App Store HDR packaging proof recorded | unverified/blocker |
| tvOS | AVKit via Metal-compatible BGRA Flutter texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | No app-specific HDR minimum or tvOS packaging proof recorded | unverified/blocker |
| macOS | media_kit AVFoundation-backed texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | No app-specific HDR minimum or signed/notarized HDR packaging proof recorded | unverified/blocker |
| Linux | in-process libmpv software RGBA texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | Existing runtime needs libmpv and its distro dependencies; HDR renderer and driver requirements unverified | unverified/blocker |
| Windows | in-process libmpv RGBA pixel-buffer texture | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | unverified/blocker | Existing bundle needs `mpv-2.dll` and dependent runtime DLLs; HDR renderer and driver requirements unverified | unverified/blocker |

The format columns are separate decisions for every target and active backend path. They are not decoder capability assertions. The Android documentation describes device-dependent supported formats, and the mpv manual describes output configuration; neither proves this app's end-to-end output path.

## Android phone/tablet

Android phone/tablet real-device/real-runtime: unverified/blocker

Current backend and renderer: `androidExoPlayer`; `Media3PlaybackPlugin.kt` owns ExoPlayer and a Flutter texture. Metadata preservation, HDR surface configuration, and SDR fallback behavior are unverified/blocker. Android's primary Media3 supported-formats documentation is conditional on device decoders and display support; no authoritative application minimum OS, hardware, or display requirement is recorded. Packaging needs an Android release artifact containing the selected Media3 path; no HDR-specific runtime constraint is yet proven.

Child-delivery plan: add normalized Media3 metadata extraction and output decision events; verify the texture/surface renderer does not reduce HDR; add unit tests for all four formats and every output state; gate a release claim on an HDR phone/tablet and HDR display with recorded OS, model, display mode, and observed output. Blockers are the missing shared contract, renderer proof, and device evidence.

## Android TV

Android TV real-device/real-runtime: unverified/blocker

Current backend and renderer: the same `androidExoPlayer` and Flutter texture path as Android phone/tablet. Metadata preservation, HDR surface configuration, tone mapping, and fallback are unverified/blocker. Android TV has no separate app-specific minimum OS, hardware, display, or HDR packaging proof in this repository.

Child-delivery plan: use the Media3 backend with a TV-safe renderer path and D-pad-safe status presentation; test normalized metadata and unsupported-device decisions; require an HDR-capable Android TV and display for HDR10, HDR10+, HLG, and Dolby Vision separately. Blockers are device/vendor conditional behavior, native surface proof, and real-display validation.

## iOS

iOS real-device/real-runtime: unverified/blocker

Current backend and renderer: `appleMediaKit` and `appleAvKit` are selected; the native AVKit plugin exposes BGRA buffers to Flutter. The current code does not prove that color metadata survives that output path or that AVFoundation tone maps on an SDR display. No authoritative application minimum iOS, hardware, display, or packaging prerequisite is recorded.

Child-delivery plan: define the AVFoundation metadata and effective-output observation boundary, prove the renderer path, and add format/state contract tests. Gate each claimed format on a physical supported iPhone, iOS version, and HDR display mode. Blockers are absent native output evidence and device validation.

## iPadOS

iPadOS real-device/real-runtime: unverified/blocker

Current backend and renderer: `appleMediaKit` and `appleAvKit` use the same current Apple texture arrangement. Metadata preservation, tone mapping, fallback, minimum OS/hardware/display requirements, and App Store packaging behavior are unverified/blocker for this app.

Child-delivery plan: implement the same AVFoundation observation contract with iPad-specific device coverage; test four formats and four output states; release-gate on physical iPad HDR display validation. Blockers are renderer proof and device-specific evidence.

## tvOS

tvOS real-device/real-runtime: unverified/blocker

Current backend and renderer: `appleAvKit` uses `AVPlayerItemVideoOutput` with BGRA and Metal compatibility in the tvOS plugin. This does not establish HDR metadata preservation, HDR output, or tone mapping. No authoritative app-specific tvOS, Apple TV hardware, connected-display, or package requirement is recorded.

Child-delivery plan: scope AVKit, the Metal-compatible renderer, and the tvOS app bundle; add native-event normalization and deterministic contract tests; gate all format claims on an Apple TV connected to an HDR display with display mode and observed output recorded. Blockers are the Flutter texture output proof and physical Apple TV validation.

## macOS

macOS real-device/real-runtime: unverified/blocker

Current backend and renderer: `desktopMediaKit` is intentionally selected on macOS and uses media_kit's AVFoundation-backed texture path; libmpv is not planned. The existing desktop feasibility record describes Metal, not HDR metadata or display output. Minimum macOS, hardware, display, and driver requirements, tone mapping, and notarized HDR packaging are unverified/blocker.

Child-delivery plan: make media_kit/AVFoundation metadata and renderer behavior observable without raw payloads; add format/state tests and a signed-bundle check; gate each claim on an HDR Mac display and real macOS runtime. Blockers are the absent end-to-end renderer and packaging evidence.

## Linux

Linux real-device/real-runtime: unverified/blocker

Current backend and renderer: `desktopLibmpv` uses libmpv in-process with `MPV_RENDER_API_TYPE_SW`, `FlPixelBufferTexture`, RGBA upload, and `hwdec=auto-safe`. The documented runtime requires `libmpv.so.2` (with `.1` or `.so` fallback) plus distro dependencies. This software texture output does not prove metadata preservation, HDR display output, or tone mapping. GPU driver, compositor, display, and portable-package HDR requirements are unverified/blocker.

Child-delivery plan: choose and document an HDR-capable libmpv renderer and Linux display-stack packaging; add runtime probe and normalized-event tests; verify the packaged runtime on Wayland and X11 with an HDR-capable display. Blockers are the current software texture path, driver/compositor variance, and absent device evidence.

## Windows

Windows real-device/real-runtime: unverified/blocker

Current backend and renderer: `desktopLibmpv` uses libmpv and an RGBA Flutter pixel-buffer texture. The documented bundle includes `mpv-2.dll`, FFmpeg DLLs, and selected rendering/audio dependencies. That packaging evidence is not HDR metadata, HDR renderer, driver, or display evidence; tone mapping and fallback are unverified/blocker.

Child-delivery plan: select an HDR-capable libmpv renderer and Windows graphics path, bundle its runtime, add normalized metadata and output-state tests, and gate release on a packaged build with an HDR monitor and recorded driver/display mode. Blockers are the current pixel-buffer path and missing real-runtime validation.

## Evidence and maintenance

Primary sources used for conditional platform behavior and future validation:

- Android Media3 supported formats: https://developer.android.com/media/media3/exoplayer/supported-formats
- Android HDR playback guidance: https://developer.android.com/media/grow/hdr-playback
- Apple AVFoundation media playback: https://developer.apple.com/documentation/avfoundation/media_playback_and_selection
- Apple AVPlayerItem: https://developer.apple.com/documentation/avfoundation/avplayeritem
- mpv manual video-output drivers: https://mpv.io/manual/master/#video-output-drivers
- mpv manual HDR options: https://mpv.io/manual/master/#options-hdr

Repository evidence is `docs/migration/playback-backend-matrix.md`, `docs/migration/desktop-libmpv-feasibility.md`, and the current backend files named above. Revisit this matrix only with source-backed implementation, automated checks, packaged runtime evidence, and a real HDR device/display result. Do not create child GitHub issues from this plan.
