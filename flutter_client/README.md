# M3U TV Flutter Client

This directory is the Flutter client for M3U TV.

## Local commands and active gates

Use the pinned Flutter binary for this rewrite work:

```bash
cd flutter_client
/tmp/flutter/bin/flutter pub get
/tmp/flutter/bin/flutter analyze
/tmp/flutter/bin/flutter test
```

The active CI baseline is intentionally limited to the Flutter client gates:

```bash
cd flutter_client
/tmp/flutter/bin/flutter pub get
/tmp/flutter/bin/dart format --output=none --set-exit-if-changed .
/tmp/flutter/bin/flutter analyze
/tmp/flutter/bin/flutter test
```


## Production toolchain baseline

The platform release source of truth is
`../docs/release/platform-release-matrix.md`. It records required SDKs,
toolchains, signing placeholders, and blockers without claiming host builds pass
before those dependencies exist.

- Android and Android TV release work needs the Android SDK, Android build tools,
  a compatible JDK, signing material supplied outside git, Play Console metadata,
  physical Android phone/tablet QA, and physical Android TV hardware QA.
  Emulator logs are supplemental only and do not satisfy the release blocker.
- Linux desktop release work needs Flutter Linux desktop support, GTK development
  files, `clang++` or an explicit `CXX`, packaged libmpv/runtime dependencies,
  and license notices.
- Windows desktop release work needs a Windows runner, Visual Studio Build Tools,
  Windows SDK, bundled mpv/FFmpeg DLLs, and Authenticode or MSIX signing.
- Apple release work needs a macOS/Xcode host, provisioning/codesigning, App
  Store or notarization preparation, and AVKit-safe playback fallback evidence.
- tvOS remains feasibility-only because the pinned Flutter toolchain has no
  first-class `flutter build tvos` command.

## Build and release smoke commands

These commands are local smoke commands only. They must not be read as production
release readiness until the matching toolchain, signing, codec review, license
review, and platform QA blockers in the release matrix are closed.

### Desktop

```bash
cd flutter_client
flutter config --enable-linux-desktop
flutter build linux

flutter config --enable-windows-desktop
flutter build windows

flutter config --enable-macos-desktop
flutter build macos
```

Desktop release candidates must bundle or declare libmpv/FFmpeg/libass
dependencies, preserve license notices, and use platform signing before public
distribution. Windows needs Authenticode/MSIX signing for Microsoft Store or
installer release. macOS needs Developer ID signing and notarization for direct
downloads, or Apple Distribution signing and sandbox review for Mac App Store.

### Android and Android TV

```bash
cd flutter_client
flutter build apk --debug
```

The debug APK is for smoke testing and sideload QA only. Play Store and Android
TV releases require signed release AAB/APK artifacts, Play Console metadata,
data-safety disclosures, TV launcher/focus checks, and native codec/license
review. Android playback defaults to Media3/ExoPlayer. The blocking fallback is m3u-editor server transcode. Android mpv/libmpv remains future-gated and non-blocking for release readiness.

Android release QA is blocked until it passes on a physical Android phone/tablet
and physical Android TV hardware. Emulator logs are supplemental only.

### iOS and iPadOS

```bash
cd flutter_client
flutter build ios --no-codesign
```

The no-codesign build is a CI/local smoke gate only. TestFlight/App Store or MDM
distribution requires Xcode archive signing, provisioning profiles, entitlements,
embedded-framework signing, and App Review. AVKit/AVPlayer plus server transcode
is the safe release path; MPVKit remains blocked until GPL/LGPL/FFmpeg, signing,
and crash-review gates pass.

### tvOS

There is no supported `flutter build tvos` command in the pinned
toolchain. tvOS remains feasibility-only until a custom Flutter tvOS embedder,
Siri Remote/gamepad forwarding, signing, and playback QA pass.

The initial test harness includes:

- `test/widget_test.dart` for fast widget tests.
- `integration_test/app_test.dart` for future device/emulator integration coverage.

## CI

The Flutter client workflow lives at `.github/workflows/ci.yml`. Its active gates run from `flutter_client/` only:

```bash
/tmp/flutter/bin/flutter analyze
/tmp/flutter/bin/flutter test
/tmp/flutter/bin/dart format --output=none --set-exit-if-changed .
```
