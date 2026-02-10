# m3u-tv Guidelines

**Stack**: React Native (TVOS 0.81), Expo 54, TypeScript.
**Platforms**: Android TV, Apple TV (tvOS).

## Context
This project is a TV frontend for the `m3u-editor` system. It focuses heavily on video playback (Live TV/VOD) and EPG (Electronic Program Guide) rendering.

## Architecture
- **Navigation**: Uses `@react-navigation/native` v7 combined with `react-tv-space-navigation` for D-pad spatial control.
- **State**: standard React hooks + Context.
- **Player**: `react-native-video` or VLC for stream playback.

## Rules

### TV Interaction
1.  **D-Pad Focus**: The app is controlled via remote. Touch events are secondary or non-existent.
2.  **Focus States**: Elements must visually change when `focused`.
3.  **Back Handling**: Handle the physical Back button on remotes correctly (pop navigation or exit).

### TypeScript & Style
- Use strict typing for all component Props.
- Use `StyleSheet.create` for styles.
- Avoid inline styles for complex views.

### Commands
- **Dev**: `corepack yarn start` (starts Expo with TV flag)
- **Lint**: `corepack yarn lint` or `corepack yarn lint:fix`
- **Typecheck**: `corepack yarn typecheck`
