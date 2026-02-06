# m3u tv

![logo](./favicon.png)

Cross-platform TV front-end player for the M3U Editor web app. Provides a convenient way to view your content on Android TV and Apple TV.

## Features

- **Live TV**: Browse and watch live TV channels with category filtering
- **Movies (VOD)**: Browse and watch on-demand movies with category filtering
- **TV Series**: Browse series with season/episode navigation
- **EPG**: Basic Electronic Program Guide for live channels
- **Settings**: Configure Xtream API connection with credential storage

## Platforms Supported

- Android TV
- Apple TV (tvOS)
- Web browsers

## Tech Stack

- React Native 0.81 (react-native-tvos)
- Expo SDK 54
- TypeScript
- React Navigation 7
- react-tv-space-navigation 6 for TV focus management
- expo-video for playback

## Getting Started

### Prerequisites

- Node.js v18+
- Yarn v4.5.0
- For Android TV: Android Studio with TV emulator
- For Apple TV: Xcode with tvOS simulator

### Installation

```bash
cd m3u-tv
yarn install
```

### Running the App

**Prebuild (optional)**

Run prebuild to generate the `Android` and `iOS` folders and native code.

```bash
EXPO_TV=1 corepack yarn prebuild --clean
```

**Web (experimental, navigation does not work well in web):**

```bash
corepack yarn web
```

**Android TV:**

```bash
corepack yarn android
```

**Apple TV:**

```bash
corepack yarn ios
```

## Configuration

### Xtream API Setup

1. Launch the app and navigate to **Settings**
2. Enter your Xtream credentials:
   - **Server URL**: Your Xtream server address (e.g., `http://example.com:8080`)
   - **Username**: Your Xtream username
   - **Password**: Your Xtream password
3. Click **Connect**

The app will authenticate and fetch your content categories. Credentials are stored locally for future sessions.

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

### Settings

- Xtream API connection management
- Connection status and statistics

## Integration with M3U Editor

This app is designed to work with the M3U Editor backend which provides Xtream API endpoints:

1. **Direct Xtream Provider**: Connect directly to your IPTV provider's Xtream API
2. **M3U Editor Server**: Connect to your M3U Editor instance which emulates the Xtream API

To use with M3U Editor, use your M3U Editor server URL and credentials from a Playlist or PlaylistAuth.

## Development

### Adding New Features

1. Components go in `packages/shared-ui/src/components/`
2. Screens go in `packages/shared-ui/src/screens/`
3. Update navigation types in `packages/shared-ui/src/navigation/types.ts`
4. Export new items from `packages/shared-ui/src/index.ts`

### Code Style

```bash
yarn format
yarn typecheck
```

## Future Enhancements

- [ ] Enhanced EPG with timeline view (planby integration)
- [ ] Search functionality
- [ ] Favorites/Watchlist
- [ ] Continue watching
- [ ] Parental controls
- [ ] Multiple profile support
- [ ] Stream quality selection
- [ ] Catchup/DVR support

---

## 🤝 Want to Contribute?

> Whether it’s writing docs, squashing bugs, or building new features, your contribution matters! ❤️

We welcome **PRs, issues, ideas, and suggestions**!\
Here’s how you can join the party:

- Follow our coding style and best practices.
- Be respectful, helpful, and open-minded.
- Respect the **CC BY-NC-SA license**.

---

## ⚖️ License

> m3u editor is licensed under **CC BY-NC-SA 4.0**:

- **BY**: Give credit where credit’s due.
- **NC**: No commercial use.
- **SA**: Share alike if you remix.

For full license details, see [LICENSE](https://creativecommons.org/licenses/by-nc-sa/4.0/).
