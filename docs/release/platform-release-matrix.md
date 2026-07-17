# Platform Release Matrix

This document is the production release source of truth for the Flutter client. It records the toolchain baseline, signing placeholders, and current blockers without claiming platform builds pass before the matching SDKs and native dependencies are present. Blocking release targets: Linux desktop, Windows desktop, Android phone/tablet, and Android TV. macOS, iOS, iPadOS, and tvOS are non-blocking gated tracks for this Desktop+Android release.

## Active CI Baseline

The only active workflow created for this release baseline is `.github/workflows/ci.yml`. It runs these Flutter gates from `flutter_client/` with the pinned Flutter binary:

```bash
/tmp/flutter/bin/flutter analyze
/tmp/flutter/bin/flutter test
```

The workflow does not run Electron builder commands, Electron scripts, or React Native/Expo release jobs. The React Native/Expo app has been fully removed; only the Flutter client remains in this repository.

## Toolchain Matrix

| Platform | Required toolchain | Signing placeholder | Current blocker | Release status |
| --- | --- | --- | --- | --- |
| Android phone/tablet | Flutter SDK at `/tmp/flutter`, Android SDK command-line tools, Android platform/build-tools, Gradle Android toolchain, Temurin JDK 17 or compatible JDK, release keystore outside git, and physical Android phone/tablet QA. | `ANDROID_KEYSTORE_PATH`, `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, and `ANDROID_KEY_PASSWORD` must come from CI secrets or a local secure store. | This task does not install or prove Android SDK availability on the executor. Release AAB/APK signing, Play Console metadata, and physical Android phone/tablet playback evidence remain open. | Blocked for production release until SDK, signing, store metadata, codec/license review, and physical Android phone/tablet smoke tests pass. Emulator logs are supplemental only. |
| Android TV | Same Android SDK/JDK baseline as Android phone/tablet plus Android TV launcher/banner metadata, D-pad focus QA, and physical Android TV hardware QA. | Same Android signing placeholders as Android phone/tablet, with Android TV Play Console listing data supplied outside git. | Android TV store readiness is not proven here. Focus, remote back handling, and playback on physical Android TV hardware still need release evidence. | Blocked for production release until physical Android TV hardware QA and signed artifact evidence exist. Emulator logs are supplemental only. |
| Linux desktop | Flutter Linux desktop support, GTK 3 development files (`gtk+-3.0` pkg-config metadata), `clang++` or configured `CXX`, CMake/Ninja, and packaged `libmpv.so.*` with runtime dependencies. | Optional package signing placeholder for deb/rpm/AppImage release keys; no private key belongs in git. | Current migration evidence shows this executor lacked GTK pkg-config metadata, `clang++`, and libmpv runtime packaging. | Blocked until Linux dependencies are installed and `/tmp/flutter/bin/flutter build linux` plus playback smoke evidence pass. |
| Windows desktop | Windows GitHub runner or equivalent Windows host, Visual Studio Build Tools with Desktop C++ workload, Windows SDK, Flutter Windows desktop support, and bundled `mpv-2.dll` plus dependent FFmpeg/runtime DLLs. | Authenticode/MSIX signing certificate placeholders must come from CI secrets or the Windows certificate store. | Windows builds are not proven on this Linux executor and mpv DLL packaging is not present. | Blocked until a Windows runner builds the Flutter bundle, signs it, and validates in-process playback or server-transcode fallback. |
| macOS desktop | NON-BLOCKING/GATED. macOS runner with Xcode command-line tools, Flutter macOS desktop support, codesign/notarization tooling, AVKit/AVPlayer-safe default, and bundled `libmpv.2.dylib` or approved MPVKit-equivalent framework only if broad-codec playback ships after review. | Apple Developer ID certificate, notarization credentials, and optional App Store distribution certificate placeholders must be supplied outside git. | macOS signing and native playback packaging are not proven here. MPVKit/libmpv remains GATED by licensing, App Store policy, crash/runtime review, native dependency review, and legal review. | NON-BLOCKING/GATED for this Desktop+Android release. It must not block Linux, Windows, Android, or Android TV release criteria. |
| iOS/iPadOS | NON-BLOCKING/GATED. macOS runner with Xcode, Flutter iOS support, provisioning profiles, device/simulator smoke targets, and AVKit/AVPlayer-safe default. | Apple Distribution certificate and provisioning profile placeholders must be supplied by CI secrets or Xcode-managed signing. | iOS release signing and App Review readiness are not proven here. MPVKit remains gated by licensing and crash review. | NON-BLOCKING/GATED for this Desktop+Android release. It must not block Linux, Windows, Android, or Android TV release criteria. |
| tvOS | NON-BLOCKING/GATED and BLOCKED. Custom Flutter tvOS embedder, Xcode tvOS runner, Siri Remote/gamepad input bridge, AVKit playback path, plugin implementation audit, and device/simulator QA are required. | Apple tvOS distribution signing placeholders must be supplied outside git. | The pinned Flutter toolchain does not expose an official `flutter build tvos` command. tvOS also needs community/custom embedder proof and missing tvOS plugin implementations resolved. | NON-BLOCKING/GATED and BLOCKED. Do not claim production readiness until the custom embedder, plugin audit, store/legal review, and remote/playback QA pass. |

## Honest Release Blockers

- Android SDK/JDK setup, signed release artifacts, Play Console metadata, physical Android phone/tablet QA, and physical Android TV hardware validation are not completed by this baseline task. Emulator logs are supplemental only.
- Android playback defaults to Media3/ExoPlayer. The blocking fallback is m3u-editor server transcode. Android mpv/libmpv remains future-gated and non-blocking for release readiness.
- Linux production packaging needs GTK development metadata, `clang++` or a configured C++ compiler, libmpv runtime packaging, and license notices before release.
- Windows production packaging needs a Windows runner/toolchain, bundled mpv/FFmpeg DLLs, and Authenticode or MSIX signing evidence.
- Apple/tvOS gates do not block the Desktop+Android release track. Apple work is a non-blocking gated track while Linux desktop, Windows desktop, Android phone/tablet, and Android TV remain the blocking release targets.
- macOS and iOS/iPadOS require Xcode host evidence, provisioning/codesigning, notarization or App Store review preparation, and an AVKit/AVPlayer-safe default before any Apple release claim.
- MPVKit/libmpv on Apple remains GATED by licensing, GPL/LGPL posture, App Store policy, crash/runtime review, native dependency review, and legal review.
- tvOS remains BLOCKED/GATED by the absence of first-class Flutter tvOS build support in the pinned toolchain, missing tvOS plugin implementation audit, Platform.isIOS vs tvOS platform detection risks, and community/custom embedder proof.
- No signing keys, store credentials, private stream URLs, or provider credentials are stored in this repository.


## Android App ID, Signing, and TV Release Metadata

- Application ID: `dev.sparkison.tv`; active Android release configuration must not use `com.example` or other template identifiers.
- `flutter_client/android/app/build.gradle.kts` reads `ANDROID_KEYSTORE_PATH`, `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, and `ANDROID_KEY_PASSWORD` from Gradle properties, environment variables, or the local ignored file `flutter_client/android/signing.properties`.
- The publication workflow enables `ANDROID_REQUIRE_RELEASE_SIGNING`. Missing signing values or a missing keystore path therefore fail publication instead of producing a debug-signed artifact. The workflow verifies the APK signer before staging and records its SHA-256 certificate digest in the job summary.
- Without `ANDROID_REQUIRE_RELEASE_SIGNING`, contributors can create a debug-signed release build for local development only and must not publish it.
- Users upgrading from a debug-signed version must uninstall the existing debug-signed app once before installing the first stable release-signed build. Uninstalling removes local app data and settings, so users must configure the app again afterward.
- Android TV launcher metadata must remain present in `flutter_client/android/app/src/main/AndroidManifest.xml`: `android.software.leanback`, optional touchscreen support, application banner, exported main activity, and `LEANBACK_LAUNCHER` category.
- Play Store and Android TV store distribution remain blocked until signed AAB/APK artifacts, Play Console metadata, data-safety declarations, codec/legal review, physical Android phone/tablet QA, and physical Android TV hardware QA are supplied as release evidence outside git.

## Dependency and License Gates

- Media3/ExoPlayer is the Android playback dependency path for this release and must keep its AndroidX license notices with generated or bundled notices for distributed artifacts.
- Flutter plugins and Flutter SDK notices must be included in each store or sideload artifact through the platform's generated license notice mechanism or an equivalent third-party notices file.
- mpv/libmpv, FFmpeg, MPVKit, and libass are desktop/native playback dependencies only where explicitly implemented and packaged. Their LGPL/GPL build flags, dynamic/static linking choices, source-offer obligations, App Store policy impact, native dependency review, and attribution notices must be reviewed before public distribution.
- GPL policy: do not ship GPL-only binaries, GPL-derived code, or Plezy reference code in a store/direct-download artifact unless the release owner explicitly accepts the GPL distribution obligations and records that decision in release evidence.
- License notices are a release gate. No Play Store, App Store, Microsoft Store, sideload, or direct-download release is complete until dependency/license notices and codec redistribution obligations are reviewed and saved with the signed artifact evidence.
