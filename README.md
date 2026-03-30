# m3u tv

![logo](./favicon.png)

Cross-platform TV front-end player for the [M3U Editor web app](https://github.com/m3ue/m3u-editor). Provides a convenient way to view your content on Android TV, Apple TV, and Desktop.

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
| Android TV | React Native (react-native-tvos) |
| Apple TV (tvOS) | React Native (react-native-tvos) |
| Desktop (Windows, macOS, Linux) | Electron + React Native Web |

## Tech Stack

- [TypeScript](https://www.typescriptlang.org/)
- [React Native 0.81](https://github.com/react-native-tvos/react-native-tvos) (react-native-tvos)
- [Expo SDK 54](https://github.com/expo/expo)
- [React Navigation 7](https://reactnavigation.org/)
- [Electron 41](https://www.electronjs.org/) for Desktop builds
- [HLS.js](https://github.com/video-dev/hls.js/) for web/desktop stream playback
- [mpv](https://mpv.io/) (embedded or external) for Desktop playback
- Custom `react-native-mpv` native module for TV playback (Android TV + tvOS)
- Native TV focus APIs (react-native-tvos) for D-pad focus management

## Getting Started

### Prerequisites

- Node.js v18+
- Yarn v4+ (`corepack enable`)
- **Android TV**: Android Studio with TV emulator
- **Apple TV**: Xcode with tvOS simulator
- **Desktop**: No additional requirements; [mpv](https://mpv.io/) or [VLC](https://www.videolan.org/) optional for external player fallback

### Installation

```bash
cd m3u-tv
corepack yarn install
```

### Running the App

#### Android TV

```bash
# Generate native project (first time or after dependency changes)
corepack yarn prebuild

corepack yarn android
```

#### Apple TV

```bash
# Generate native project (first time or after dependency changes)
corepack yarn prebuild

corepack yarn ios
```

#### Desktop (Electron) — Development

```bash
corepack yarn electron:dev
```

This exports the Expo web bundle and launches it in Electron.

#### Desktop (Electron) — Production Build

```bash
corepack yarn electron:build
```

Outputs to `release/`:

| OS | Format |
|---|---|
| Linux | AppImage, `.deb` |
| Windows | NSIS installer, portable `.exe` |
| macOS | `.dmg` |

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

## Desktop Playback

On Desktop, streams are handled in two ways:

1. **Embedded mpv** (default): mpv renders directly inside the Electron window via IPC.
2. **External player fallback**: If embedded mpv is unavailable, the app falls back to launching mpv, VLC, or the system default handler.

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

## Project Structure

```
m3u-tv/
├── electron/           # Electron main process (Desktop)
│   ├── main.js         # BrowserWindow, IPC handlers, mpv integration
│   ├── mpvController.js
│   └── preload.js
├── modules/
│   └── react-native-mpv/   # Custom native mpv module (Android TV + tvOS)
├── plugins/            # Expo config plugins
├── src/
│   ├── components/     # Shared UI components
│   ├── context/        # React context providers
│   ├── hooks/          # Custom hooks (platform-split where needed)
│   ├── navigation/     # React Navigation setup and types
│   ├── screens/        # Screen components (platform-split where needed)
│   ├── services/       # API, cache, storage services
│   ├── theme/          # Colors, typography, spacing
│   ├── types/          # TypeScript types
│   └── utils/          # Utilities
└── app.config.js       # Expo config
```

## Development

### Code Style

```bash
corepack yarn lint
corepack yarn lint:fix
corepack yarn typecheck
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
- [x] Desktop (Electron) support
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
