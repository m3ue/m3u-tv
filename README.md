# M3U TV

![logo](./favicon.png)

Cross-platform TV front-end player for the M3U Editor app. Provides a convenient way to view your content on Android TV, Apple TV and Fire TV.

## Features

- **Live TV**: Browse and watch live TV channels with category filtering
- **Movies (VOD)**: Browse and watch on-demand movies with category filtering
- **TV Series**: Browse series with season/episode navigation
- **EPG**: Basic Electronic Program Guide for live channels
- **Settings**: Configure Xtream API connection with credential storage

## Platforms Supported

- Android TV
- Apple TV (tvOS)
- Fire TV (Fire OS)
- Fire TV (Vega OS)
- Web browsers

## Tech Stack

- React Native 0.74 (react-native-tvos)
- Expo SDK 51
- TypeScript
- React Navigation 6
- react-tv-space-navigation for TV focus management
- react-native-video for playback

## Project Structure

```
m3u-tv/
├── apps/
│   ├── expo-multi-tv/    # Main TV app (Expo)
│   └── vega/             # Fire TV Vega variant
├── packages/
│   └── shared-ui/        # Shared components, screens, services
│       ├── src/
│       │   ├── components/   # Reusable UI components
│       │   ├── context/      # React contexts (Xtream)
│       │   ├── navigation/   # Navigation configuration
│       │   ├── screens/      # App screens
│       │   ├── services/     # API services (Xtream)
│       │   ├── theme/        # Colors, typography, spacing
│       │   └── types/        # TypeScript types
│       └── package.json
└── package.json
```

## Getting Started

### Prerequisites

- Node.js v18+
- Yarn v4.5.0
- For Android TV: Android Studio with TV emulator
- For Apple TV: Xcode with tvOS simulator
- For Fire TV: Fire TV device or emulator

### Installation

```bash
cd m3u-tv
yarn install
```

### Running the App

**Web (for development):**
```bash
yarn dev:web
```

**Android TV:**
```bash
yarn dev:android
```

**Apple TV:**
```bash
yarn dev:ios
```

**Fire TV Vega:**
```bash
yarn dev:vega
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

## License

MIT
