# m3u tv

![logo](./favicon.png)

Cross-platform TV front-end player for the [M3U Editor web app](https://github.com/m3ue/m3u-editor). The primary client is the Flutter app in `flutter_client/`.

## Features

- **Live TV**: Browse and watch live TV channels with category filtering
- **Movies (VOD)**: Browse and watch on-demand movies with category filtering
- **TV Series**: Browse series with season/episode navigation
- **EPG**: Electronic Program Guide with timeline view for live channels
- **Search**: Search across live channels, movies, and series
- **Favorites**: Save and manage favorite channels and content
- **Continue Watching**: Resume playback from where you left off
- **Settings**: Configure Xtream API connection with secure credential storage

## Platforms Supported

| Platform | Status |
|---|---|
| Android TV | Supported — ExoPlayer via Media3 |
| Android / iOS / iPadOS | Supported |
| Apple TV (tvOS) | Supported — AVKit backend via [flutter-tvos](https://github.com/fluttertv/flutter-tvos) |
| Desktop (macOS / Linux / Windows) | Supported — libmpv via media_kit |

## Tech Stack

- [Flutter](https://flutter.dev/) and Dart in `flutter_client/`
- Flutter widget, service, playback, and migration test suites covering parity behavior
- In-process playback architecture with platform backend fallbacks documented in `docs/migration/playback-backend-matrix.md`

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) on your PATH
- **Android / Android TV**: Android Studio with an emulator or device
  - Running M3U Editor via Docker locally? Access it from the emulator at `http://10.0.2.2:36400`. Run `adb reverse tcp:36400 tcp:36400` so images and streams work too.
- **Apple platforms (iOS, macOS, tvOS)**: Xcode 15+
- **Apple TV (tvOS)**: [flutter-tvos CLI](#apple-tv-tvos) installed (separate from the Flutter SDK)

### Installation

```bash
cd flutter_client
flutter pub get
```

### Running the App

```bash
# Android / iOS / desktop
flutter run

# Apple TV simulator — see the tvOS section below for first-time setup
flutter-tvos run -d <device-id>
```

Quality gates:

```bash
cd flutter_client
dart format .
flutter analyze
flutter test
```

## Configuration

### Xtream API Setup

1. Launch the app and navigate to **Settings**
2. Enter your Xtream credentials:
   - **Server URL**: Your Xtream server address (e.g., `http://example.com:8080`)
   - **Username**: Your Xtream username
   - **Password**: Your Xtream password
3. Click **Connect**

The app will authenticate and fetch your content categories. Credentials are stored securely for future sessions.

## Screens Overview

### Home

- Welcome screen with quick access to content
- Shows preview rows of Live TV, Movies, and Series when connected

### Live TV

- Grid of live channels organized by category
- Category filter tabs at the top
- Select a channel to start playback

### Movies (VOD)

- Grid of movies organized by category
- Shows ratings and posters
- Select a movie to start playback

### Series

- Grid of TV series organized by category
- Select a series to view seasons and episodes
- Episode browser with thumbnails

### Search

- Search across live channels, movies, and series from a single screen

### Settings

- Xtream API connection management
- Connection status and statistics

Keyboard shortcuts:

| Shortcut | Action |
|---|---|
| `F11` | Toggle fullscreen |
| `Cmd/Ctrl+Q` | Quit |

## Integration with M3U Editor

This app is designed to work with the M3U Editor backend which provides Xtream API endpoints:

1. **Direct Xtream Provider**: Connect directly to your IPTV provider's Xtream API
2. **M3U Editor Server**: Connect to your M3U Editor instance which emulates the Xtream API

To use with M3U Editor, use your M3U Editor server URL and credentials from a Playlist or PlaylistAuth.


## Development

### Code Style

```bash
cd flutter_client
dart format ./
flutter analyze
flutter test
```

### Apple TV (tvOS)

tvOS builds use [flutter-tvos](https://github.com/fluttertv/flutter-tvos) — a drop-in companion CLI that targets tvOS instead of iOS. Install it once, alongside your normal Flutter SDK.

**Install flutter-tvos** (one-time, version 1.3.0 / Flutter 3.44.1):

```bash
git clone https://github.com/fluttertv/flutter-tvos.git ~/flutter-tvos
```

Add to your shell profile (`~/.zshrc` or `~/.bash_profile`):

```bash
export PATH="$HOME/flutter-tvos/bin:$PATH"
```

Then reload and download the tvOS engine artifacts:

```bash
source ~/.zshrc          # or restart your terminal
flutter-tvos precache
flutter-tvos doctor      # should show ✓ Flutter and ✓ tvOS toolchain
```

**Run on the Apple TV simulator:**

```bash
cd flutter_client
flutter-tvos devices     # find your simulator ID
flutter-tvos run -d <simulator-id>
```

**Update flutter-tvos** when a new version ships:

```bash
flutter-tvos upgrade
```

> `flutter-tvos` and `flutter` are independent CLIs. `flutter-tvos` commands only target tvOS; everything else (`flutter run`, `flutter build apk`, etc.) continues to use the standard `flutter` CLI as normal.

### Adding New Screens

1. Add the screen widget in `lib/features/<feature>/`
2. Add the route name to `lib/navigation/route_names.dart`
3. Register it in `lib/navigation/app_router.dart`

## Future Enhancements

- [x] Enhanced EPG with timeline view
- [x] Continue watching
- [x] Favorites/Watchlist
- [x] Search functionality
- [x] Apple TV (tvOS)
- [ ] Parental controls
- [ ] Stream quality selection
- [ ] Catchup/DVR support

---

## Want to Contribute?

> Whether it's writing docs, squashing bugs, or building new features, your contribution matters!

We welcome **PRs, issues, ideas, and suggestions**!\
Here's how you can join the party:

- Follow our coding style and best practices.
- Be respectful, helpful, and open-minded.
- Respect the **CC BY-NC-SA license**.

---

## License

> m3u editor is licensed under **CC BY-NC-SA 4.0**:

- **BY**: Give credit where credit's due.
- **NC**: No commercial use.
- **SA**: Share alike if you remix.

For full license details, see [LICENSE](https://creativecommons.org/licenses/by-nc-sa/4.0/).
