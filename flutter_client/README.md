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

## Release builds

All release builds require the Trakt credentials passed via `--dart-define`.
Set the environment variables first (see [Trakt setup](#trakt-setup)), then use the commands below.

### Android TV / Android (release APK / App Bundle)

```bash
# App Bundle (Play Store / sideload)
flutter build appbundle --release \
  --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
  --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET

# APK (direct sideload)
flutter build apk --release \
  --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
  --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET
```

### iOS (release archive for App Store)

```bash
flutter build ipa --release \
  --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
  --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET
```

Open `build/ios/archive/Runner.xcarchive` in Xcode to distribute via App Store Connect.

### Apple TV / tvOS (release archive for App Store)

```bash
flutter-tvos build tvos --release \
  --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
  --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET
```

Open the resulting `.xcarchive` in Xcode to distribute via App Store Connect.

### macOS (release archive for Mac App Store)

```bash
flutter build macos --release \
  --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
  --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET
```

### Linux

```bash
flutter build linux --release \
  --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
  --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET
```

### Windows

```bash
flutter build windows --release \
  --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
  --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET
```

## Updating icons and splash screens

All platform icons and splash screens are generated from the SVG source at `../logo.svg`.
Do not hand-edit the generated PNGs — run the script instead.

### Prerequisites

```bash
brew install librsvg imagemagick
```

### Run the generator

```bash
bash scripts/setup-icons.sh
```

This script:
1. Renders `logo.svg` → transparent PNGs at the required sizes
2. Builds `assets/icons/icon.png` (opaque, for iOS/macOS/Windows) and `adaptive-icon.png` / `splash-icon.png` (transparent)
3. Runs `dart run flutter_launcher_icons` — Android, iOS, macOS, Web, Windows, Linux
4. Runs `dart run flutter_native_splash:create` — Android + iOS splash screens
5. Generates the **tvOS layered icons** (Back / Middle / Front layers for the parallax effect) and the **Top Shelf image** — these are not covered by `flutter_launcher_icons`

After running, rebuild the tvOS target in Xcode to pick up the refreshed icons.

### tvOS icon sizes (for reference)

| Asset | Size |
|---|---|
| App Icon — Large (focused) | 1280 × 768 px per layer |
| App Icon — Small (home shelf) | 400 × 240 px (1x), 800 × 480 px (2x) per layer |
| Top Shelf Image | 1920 × 720 px |

## Trakt setup

Trakt credentials are injected at compile time via `--dart-define` and are never stored in source control.

1. Register an app at <https://trakt.tv/oauth/applications>
   - Redirect URI: `urn:ietf:wg:oauth:2.0:oob`
   - Scopes: `/scrobble` only
2. Add to your shell profile (`~/.zshrc` or `~/.zprofile`):
   ```bash
   export TRAKT_CLIENT_ID="your_client_id"
   export TRAKT_CLIENT_SECRET="your_client_secret"
   ```
3. Re-source your profile: `source ~/.zshrc`
4. Pass the defines on every `flutter run` / `flutter build`:
   ```bash
   flutter run \
     --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
     --dart-define=TRAKT_CLIENT_SECRET=$TRAKT_CLIENT_SECRET \
     -d <device-id>
   ```

For CI (GitHub Actions), store `TRAKT_CLIENT_ID` and `TRAKT_CLIENT_SECRET` as repository secrets and reference them in your workflow:

```yaml
--dart-define=TRAKT_CLIENT_ID=${{ secrets.TRAKT_CLIENT_ID }}
--dart-define=TRAKT_CLIENT_SECRET=${{ secrets.TRAKT_CLIENT_SECRET }}
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
