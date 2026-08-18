# M3U TV - Flutter Client

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
dart format lib test
flutter analyze lib test
flutter test
```

Scope `format`/`analyze` to `lib test` rather than `.` - if you've run an iOS/macOS build locally, `ios/build/` and `macos/build/` contain vendored SPM checkouts (e.g. `firebase_messaging`) with their own `pubspec.yaml`, which the analyzer treats as separate projects to fully lint/type-check. `analyzer.exclude` globs can't suppress this once a directory has its own `pubspec.yaml`, so directory scoping is the only reliable fix.

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

If you hit `Package product 'firebase-core' requires minimum platform version 15.0 ... but this target supports 13.0`, set this for every iOS command (`flutter clean`, `flutter pub get`, `flutter run`, `flutter build ios`, `pod install`):

```bash
export FLUTTER_SWIFT_PACKAGE_MANAGER=false
```

This is a Flutter SDK limitation, not a project misconfig: Flutter hardcodes the auto-generated `FlutterGeneratedPluginSwiftPackage` wrapper's minimum iOS version to 13.0 regardless of `IPHONEOS_DEPLOYMENT_TARGET` (which is correctly 15.0 here), and `firebase_core`/`firebase_messaging` require 15.0. It regenerates on every `flutter clean`/`pub get`, so the error resurfaces even if you haven't touched anything. Disabling SPM routes all plugins - Firebase included, via its still-published podspec - through CocoaPods instead, which honors the Podfile's real `platform :ios, '15.0'`. CI (`release.yml`) sets this env var for the `build-ios` job already.

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

#### Updating a ported plugin (`packages/*_tvos`)

`packages/flutter_secure_storage_tvos`, `packages/sqflite_tvos`, and `packages/wakelock_plus_tvos` are manual tvOS ports of upstream iOS/macOS plugin implementations, generated with `flutter-tvos plugin port`. Pub has no idea these forks exist, so bumping the upstream package (`flutter_secure_storage_darwin`, `sqflite_darwin`, `wakelock_plus`, ...) in `pubspec.yaml` never updates the fork automatically - `test/release/tvos_port_drift_test.dart` exists to catch that drift and fail CI when it happens.

To re-port after that test fails, run `plugin port` against the **upstream** iOS/macOS package - not the existing `_tvos` fork itself:

```bash
flutter-tvos plugin port --from-pub sqflite_darwin
```

Passing the fork's own name fails, since it already targets tvOS and there's nothing left to port from it:

```
flutter-tvos plugin port --from-pub sqflite_tvos
sqflite_tvos already targets tvOS. Pass an iOS or macOS plugin instead.
```

Each fork's `PORTING_REPORT.md` records which upstream package and version it came from (see the `Source:` line) - use that to know which package name to pass. After porting:

1. Diff the freshly generated output against `packages/<name>_tvos/` and merge in the native changes by hand - the porter regenerates from scratch, so any prior manual fixes listed under that package's `PORTING_REPORT.md` "Manual review items" may need to be reapplied.
2. Update `packages/<name>_tvos/PORTING_REPORT.md`'s `Source:` line to the new upstream version.
3. Bump `packages/<name>_tvos/pubspec.yaml`'s version and add a `CHANGELOG.md` entry.
4. Run `flutter test test/release/tvos_port_drift_test.dart` to confirm the fork is back in sync.

## Release builds

Release builds work with no extra setup — the app ships with a built-in public Trakt
client id. See the [Trakt setup](#trakt-setup) note at the end of this section if
you're maintaining a fork and want to use your own client id instead.

### Android TV / Android (release APK / App Bundle)

```bash
# App Bundle (Play Store / sideload)
flutter build appbundle --release

# APK (direct sideload)
flutter build apk --release
```

`release.yml` builds iOS and tvOS on every tag push too, but only as **unsigned** sideload artifacts attached to the GitHub Release (see `build-ios`/`build-tvos` jobs) - it does not submit to App Store Connect. Actual App Store/TestFlight submission for iOS and tvOS is a manual step you run locally, below.

### iOS (manual App Store submission)

Build, archive, and export in one step from the CLI:

```bash
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist
```

(If you're overriding `TRAKT_CLIENT_ID` for a fork, note that `--dart-define` values are baked into `ios/Flutter/Generated.xcconfig` only as a side effect of a CLI `flutter build`/`flutter run` - if you skip straight to Xcode's **Archive** action without running one first, the archive silently ships without your override (whatever was last written to that file, possibly nothing).)

This produces `build/ios/ipa/Runner.ipa` - upload it with [Transporter](https://apps.apple.com/app/transporter/id1450874784) or `xcrun altool --upload-app`.

Prefer Xcode's Organizer instead? Run the `flutter build ipa` command above first (so the defines are baked in and the archive already exists at `build/ios/archive/Runner.xcarchive`), then open it in Xcode and **Distribute App → App Store Connect**. Do not archive directly from a bare Xcode session that skipped the CLI step.

`ios/ExportOptions.plist` (method `app-store-connect`, your Team ID) is checked into the repo. Use `app-store-connect`, not the older `app-store` value - Xcode 26 treats it as deprecated and `flutter build ipa`'s IPA-export step fails silently on it (`xcodebuild -exportArchive` alone still works either way, but the wrapper doesn't).

### Apple TV / tvOS (manual App Store submission)

This project signs the tvOS target **Manually**, pinned to the `M3U TV (tvOS)` distribution profile (Signing & Capabilities in Xcode) - that's the config that has actually produced working App Store submissions. `flutter-tvos build tvos --release`, however, always forces `CODE_SIGN_STYLE=Automatic` on the `xcodebuild` invocation it runs internally, with no way to opt out - so running it end-to-end **will fail** with `Runner has conflicting provisioning settings`, unrelated to whether your Apple ID is signed into Xcode.

Run it anyway, for one reason only: the Dart AOT compile step completes and writes `tvos/Flutter/App.framework` to disk *before* that incompatible `xcodebuild` call runs, so the framework comes out correct even though the command as a whole reports failure:

```bash
flutter-tvos build tvos --release
```

Ignore the failure output. A fresh `tvos/Flutter/App.framework` with the Trakt client id compiled in is what you need, and it's already there. Then open `tvos/Runner.xcworkspace` in Xcode and **Product → Archive → Distribute App**, exactly as before; the project's own "Embed App.framework" build phase picks up the file that's already on disk and doesn't re-run flutter-tvos itself, so the Manual-signing Archive path is untouched by any of this.

If you'd rather not rely on flutter-tvos's `build tvos` reporting a "failure" that isn't one, the fully-CLI archive/export path also works once you're archiving (not just building):

```bash
xcodebuild archive \
  -workspace tvos/Runner.xcworkspace -scheme Runner \
  -sdk appletvos -configuration Release \
  -archivePath build/Runner.xcarchive \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath build/Runner.xcarchive \
  -exportOptionsPlist tvos/ExportOptions.plist \
  -exportPath build/export
```

Upload `build/export/Runner.ipa` the same way as iOS. `tvos/ExportOptions.plist` is checked into the repo alongside the iOS one.

If a plain `xcodebuild archive`/`-allowProvisioningUpdates` run (not `flutter-tvos build`) ever reports `Communication with Apple failed: Your team has no devices...`, that's not really about registering a device - `flutter-tvos` (and a bare `xcodebuild` invocation with no `DEVELOPMENT_TEAM` build setting) resolves the team from whichever certificate your local keychain happens to surface first, which can be a different team than this project's. Pass the right one explicitly and it goes away:

```bash
export DEVELOPMENT_TEAM=5AMT94T836   # this project's team ID
```

> **Run `flutter-tvos run -d <simulator-id>` at least once before opening Xcode for simulator debugging.** `flutter-tvos` swaps the entire `Flutter.xcframework` per build mode/environment (debug/release × device/simulator); a stale one left over from a prior release build breaks simulator runs in Xcode with a "no library for this platform" error. `flutter-tvos build tvos --release` (used above to bake in dart-defines) doesn't fix this itself - its own `xcodebuild` step always fails against this project's Manual-signing config, so it never gets to regenerate the simulator slice. If you need to go back to simulator debugging afterward, run `flutter-tvos run -d <simulator-id>` again to restore it. See the [tvOS setup section in the root README](../README.md#apple-tv-tvos) for one-time install instructions. Likewise, never run `pod install` by hand in `tvos/` - it reads the plugin list from `.flutter-plugins-dependencies`, which is only populated correctly as a side effect of `flutter-tvos build`/`run`; running `pod install` standalone (before that list is populated) silently strips tvOS-only pods like `sqflite_tvos` from `Podfile.lock`. If pods look wrong, re-run `flutter-tvos build tvos`/`run` - don't call `pod install` directly.

### macOS (via GitHub Actions - not the Mac App Store)

Unlike iOS/tvOS/Android, macOS release builds are never submitted to an app store by hand. Every `v*.*.*` tag push runs the `build-macos` job in `.github/workflows/release.yml` end-to-end: release build, code-sign with the Developer ID Application certificate, notarize via `notarytool`, staple the ticket, and publish the DMG straight to the GitHub Release - the same all-desktop-via-CI path Linux and Windows use below. There is no separate manual macOS release step.

To build a local macOS release for testing only (not signed or notarized, so not distributable):

```bash
flutter build macos --release
```

### Linux

```bash
flutter build linux --release
```

### Windows

```bash
flutter build windows --release
```

## Updating icons and splash screens

All platform icons and splash screens are generated from the SVG source at `../logo.svg`.
Do not hand-edit the generated PNGs - run the script instead.

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
3. Runs `dart run flutter_launcher_icons` - Android, iOS, macOS, Web, Windows, Linux
4. Runs `dart run flutter_native_splash:create` - Android + iOS splash screens
5. Generates the **tvOS layered icons** (Back / Middle / Front layers for the parallax effect) and the **Top Shelf image** - these are not covered by `flutter_launcher_icons`

After running, rebuild the tvOS target in Xcode to pick up the refreshed icons.

### tvOS icon sizes (for reference)

| Asset | Size |
|---|---|
| App Icon - Large (focused) | 1280 × 768 px per layer |
| App Icon - Small (home shelf) | 400 × 240 px (1x), 800 × 480 px (2x) per layer |
| Top Shelf Image | 2320 × 720 px (Wide) |

## Generating store screenshots

Store-ready screenshots and marketing assets are generated from the source images in `screenshots/app-screenshots/` and the SVG logo at `../logo.svg`. Do not hand-edit the output files - run the script instead.

### Prerequisites

```bash
brew install imagemagick librsvg
```

### Run the generator

```bash
bash scripts/generate-screenshots.sh
```

Output is written to `screenshots/store/` with the following structure:

| Platform | Directory | Notes |
|---|---|---|
| Apple tvOS | `apple/tvos/1920x1080/` | Required for all submissions |
| Apple tvOS 4K | `apple/tvos/3840x2160/` | Optional - copied from source |
| Apple iPhone 6.7" | `apple/ios/6.7in-1290x2796/` | Required for iPhone 14+/15+ |
| Apple iPhone 6.5" | `apple/ios/6.5in-1242x2688/` | Required for older iPhones |
| Apple iPhone 5.5" | `apple/ios/5.5in-1242x2208/` | Optional legacy device class |
| Apple macOS | `apple/macos/1440x900/` | |
| Android TV | `google/android-tv/1920x1080/` | Required |
| Android TV (legacy) | `google/android-tv/1280x720/` | Optional |
| Android Phone | `google/android-phone/1080x2340/` | |
| Google Play Feature Graphic | `google/android-feature-graphic/feature-graphic.png` | Required - single 1024 × 500 image |
| Android TV Banner | `google/android-tv-banner/tv-banner.png` | Required for TV listing - 1280 × 720 |

The feature graphic and TV banner are generated from `../logo.svg` on the app's diagonal gradient background (`#1a1528` → `#09090b`) rather than from screenshots.

### Source image conventions

| Filename pattern | Used for |
|---|---|
| `tv*.png` | tvOS + Android TV screenshots (source: 3840 × 2160) |
| `mobile*.png` | iOS + Android Phone screenshots (source: 1206 × 2622) |
| `desktop*.png` | macOS screenshots (source: 1707 × 1160) |

## Trakt setup

Trakt uses a public client id for device authorization in this app. The app ships with a default client id built in, so Trakt scrobbling works out of the box with no `--dart-define` needed. A client id is not a secret — it's sent as the `trakt-api-key` header on every API request, the same way it's visible to anyone who inspects the built app.

To use your own registered app instead of the built-in default:

1. Register an app at <https://trakt.tv/oauth/applications>
   - Redirect URI: `urn:ietf:wg:oauth:2.0:oob`
   - Scopes: `/scrobble` only
2. Add to your shell profile (`~/.zshrc` or `~/.zprofile`):
   ```bash
   export TRAKT_CLIENT_ID="your_client_id"
   ```
3. Re-source your profile: `source ~/.zshrc`
4. Pass the define on every `flutter run` / `flutter build`:
   ```bash
   flutter run \
     --dart-define=TRAKT_CLIENT_ID=$TRAKT_CLIENT_ID \
     -d <device-id>
   ```

`.github/workflows/release.yml` does not pass `TRAKT_CLIENT_ID` at all — release builds use the built-in default. If you fork this repo and want your CI to build with your own app instead, add `TRAKT_CLIENT_ID` as a repository secret and add the define back to the relevant `flutter build`/`flutter-tvos build` steps:

```yaml
--dart-define=TRAKT_CLIENT_ID=${{ secrets.TRAKT_CLIENT_ID }}
```

## Developer dart-defines

These compile-time flags are for local development and debugging. Pass them via `--dart-define` - they default to off and are never required for normal builds.

| Flag | Default | Purpose |
|---|---|---|
| `TRAKT_CLIENT_ID` | built-in app client id | Overrides the default Trakt API client ID. See [Trakt setup](#trakt-setup). |
| `M3U_TV_SHOW_PLAYBACK_DIAGNOSTICS` | `false` | Renders the in-player backend diagnostics panel and fallback reason badge. Useful when debugging playback fallback behaviour. |

Example enabling diagnostics on a debug run:

```bash
flutter run \
  --dart-define=M3U_TV_SHOW_PLAYBACK_DIAGNOSTICS=true \
  -d <device-id>
```

## Project structure

```
lib/
  app/            App shell, device type detection
  features/       Screen-level widgets (live_tv, vod, series, player, …)
  l10n/           ARB source files + generated AppLocalizations
  navigation/     Router, route names, PlayerArgs
  playback/       Platform playback adapters and orchestrator
  providers/      Riverpod providers (app_providers.dart - single source of truth)
  services/       Domain models, Xtream API, EPG, AppStateController
  shared/         Reusable UI widgets
tvos/             Apple TV (tvOS) Xcode runner
ios/              iOS Xcode runner
android/          Android Gradle project
packages/         Local Flutter packages (flutter_secure_storage_tvos, …)
test/             Unit and widget tests
```

## State architecture

State is managed with **Riverpod 2**. The key split:

| Concern | Who handles it |
|---|---|
| Reactive data reads (channels, isConfigured, etc.) | Riverpod providers in `lib/providers/app_providers.dart` |
| Business logic / mutations (connect, disconnect, etc.) | `AppStateController` - called via callbacks passed from `AppShell` |
| Service instances (EPG, favorites, etc.) | `AppStateController` owns them; providers expose stable refs via `ref.read` |

**The rule:** feature screens extend `ConsumerStatefulWidget` and read all display data via `ref.watch(someProvider)`. They never hold or accept an `AppStateController` reference. Actions arrive as typed callbacks in the constructor.

See `CLAUDE.md` for the full provider list and the test pattern.

## Localization

The app is fully localized using Flutter `gen_l10n`. Supported languages: **English** (`en`), **German** (`de`), **Spanish** (`es`), **French** (`fr`), **Simplified Chinese** (`zh`). Users can override the system language in Settings → Language.

### Adding or updating strings

1. Edit `lib/l10n/app_en.arb` (source of truth) - add the new key and English value.
2. Add the translated key to all other ARB files (`app_de.arb`, `app_es.arb`, `app_fr.arb`, `app_zh.arb`).
3. Regenerate:
   ```bash
   flutter gen-l10n
   ```
4. Use `AppLocalizations.of(context).<key>` in your widget. Never hard-code user-visible strings in widget trees.

### Adding a new language

1. Create `lib/l10n/app_<locale>.arb` with all keys from `app_en.arb` translated.
2. Add `Locale('<locale>')` to `supportedLocales` in `l10n.yaml`.
3. Run `flutter gen-l10n`.
4. Add a language chip to the picker in `settings_screen.dart`.

### Tests

Every `MaterialApp` that renders a localized widget must include:

```dart
localizationsDelegates: AppLocalizations.localizationsDelegates,
supportedLocales: AppLocalizations.supportedLocales,
```

## Android release notes

See [../docs/release/platform-release-matrix.md](../docs/release/platform-release-matrix.md) for full release gates.

- Android playback now uses native mpv (`PlaybackBackend.androidMpv`) as the primary path, with Media3/ExoPlayer as the automatic fallback and m3u-editor server transcode as the final fallback when direct playback fails.
- Native mpv playback has only been confirmed via limited manual testing on physical Android TV hardware; subtitle rendering, HDR, and broader device/codec QA remain open.
- Emulator logs are supplemental only. Release sign-off requires physical Android phone/tablet QA and physical Android TV hardware QA on the target API level.

## Toolchain versions

| Tool | Version |
|---|---|
| Flutter SDK | `^3.12.0` (see `pubspec.yaml`) |
| flutter-tvos | 1.3.0 (Flutter 3.44.1) |
| Dart | `^3.12.0` |
