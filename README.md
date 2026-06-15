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

| Platform | Method |
|---|---|
| Android TV | Flutter client (`flutter_client/`) |
| Desktop (Linux/macOS/Windows) | Flutter client (`flutter_client/`) with in-process libmpv feasibility gates |
| Android/iOS/iPadOS | Flutter client (`flutter_client/`) |
| Apple TV (tvOS) | Migration feasibility tracked; Flutter tvOS remains gated on embedder support |

## Tech Stack

- [Flutter](https://flutter.dev/) and Dart in `flutter_client/`
- Flutter widget, service, playback, and migration test suites covering parity behavior
- In-process playback architecture with platform backend fallbacks documented in `docs/migration/playback-backend-matrix.md`

## Getting Started

### Prerequisites

- Flutter SDK available via the CLI (ability to run `flutter` and `dart` commands)
- **Android/Android TV**: Android Studio with emulator or device when running platform builds
   - **NOTE**: use `http://10.0.2.2` to access `localhost` via the emulator. E.g., if running the editor via `php artisan serve` on your local machine, you can access it in the emulator via: `http://10.0.2.2:8000`.
- **Apple platforms**: Xcode when running iOS/macOS feasibility builds

### Installation

```bash
cd m3u-tv
cd flutter_client
flutter pub get
```

### Running the App

#### Flutter client

```bash
flutter run
```

Quality gates for the primary client:

```bash
flutter analyze
flutter test
dart format ./
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
flutter analyze
flutter test
```

### Adding New Screens

1. Add the screen component in `src/screens/`
2. Add the route to `src/navigation/types.ts`
3. Register it in `src/navigation/AppNavigator.tsx`
4. Export from `src/screens/index.ts`

## Future Enhancements

- [x] Enhanced EPG with timeline view
- [x] Continue watching
- [x] Favorites/Watchlist
- [x] Search functionality
- [ ] Desktop builds
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
