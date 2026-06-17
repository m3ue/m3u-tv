# M3U TV — Flutter Client

Flutter app for M3U TV targeting Android TV, iOS, macOS, Linux, Windows, and Apple TV (tvOS).

## Quick start

```bash
cd flutter_client
flutter pub get
flutter run
```

## Quality gates

Run these from `flutter_client/` before every PR:

```bash
dart format .
flutter analyze
flutter test
```

## Platform commands

### Android / Android TV

```bash
flutter run                       # debug on connected device/emulator
flutter build apk --debug         # debug APK for sideload QA
```

### iOS / iPadOS

```bash
flutter run                       # debug on simulator or device
flutter build ios --no-codesign   # CI smoke build
```

### macOS / Linux / Windows

```bash
flutter run -d macos
flutter run -d linux
flutter run -d windows
```

### Apple TV (tvOS)

tvOS builds require the [flutter-tvos CLI](https://github.com/fluttertv/flutter-tvos). See the [tvOS setup section in the root README](../README.md#apple-tv-tvos) for one-time install instructions.

Once installed:

```bash
flutter-tvos devices              # list available Apple TV simulators
flutter-tvos run -d <device-id>   # run on simulator (hot reload works)
flutter-tvos build tvos --simulator --debug   # build only
```

## Project structure

```
lib/
  app/            App shell, device type detection
  features/       Screen-level widgets (live_tv, vod, series, player, …)
  navigation/     Router, route names, PlayerArgs
  playback/       Platform playback adapters and orchestrator
  services/       Domain models, Xtream API, EPG, state controller
  shared/         Reusable UI widgets
tvos/             Apple TV (tvOS) Xcode runner
ios/              iOS Xcode runner
android/          Android Gradle project
packages/         Local Flutter packages (flutter_secure_storage_tvos, …)
test/             Unit and widget tests
```

## Android release notes

See [../docs/release/platform-release-matrix.md](../docs/release/platform-release-matrix.md) for full release gates.

- Android playback defaults to Media3/ExoPlayer. The blocking fallback is m3u-editor server transcode when direct playback fails.
- Android mpv/libmpv remains future-gated and non-blocking.
- Emulator logs are supplemental only. Release sign-off requires physical Android phone/tablet QA and physical Android TV hardware QA on the target API level.

## Toolchain versions

| Tool | Version |
|---|---|
| Flutter SDK | `^3.12.0` (see `pubspec.yaml`) |
| flutter-tvos | 1.3.0 (Flutter 3.44.1) |
| Dart | `^3.12.0` |
